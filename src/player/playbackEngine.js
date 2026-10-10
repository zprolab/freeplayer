// PlaybackEngine — the playback stream, kept free of React.
//
// Owns everything that is true regardless of who is rendering:
//   - the <audio> element and its source (`media://<encoded path>`)
//   - the Web Audio graph wiring (EQ → analyser → gain)
//   - the media event surface (play/pause/timeupdate/durationchange/error/ended)
//   - play sessions and listening accounting (playStart/playEnd)
//
// It knows nothing about queues, play modes or React state: the UI layer decides
// WHAT to play and calls play(track); the engine reports what happened through
// subscribe(). That boundary is what makes the backend replaceable — swapping
// Web Audio for a native CoreAudio engine should only mean reimplementing this
// class, not touching components. (The queue-navigation decision stays in
// playQueue.js as pure functions for the same reason.)
//
// Audio accounting uses played-position, not wall-clock:
//   playedMs    — only accumulates while the element is actually playing, so a
//                 pause/background/sleep no longer counts as listening time
//   maxPosition — highest position reached, so a skip reports a low percentage
//                 and seeking back does not lower it

import { audioEngine } from '../audio/audioEngine';

const MEDIA_ERROR_CODES = {
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// `media://` carries the whole path percent-encoded: encodeURI leaves '#' and
// '?' unescaped, which WebKit reads as fragment/query and truncates the path.
export function mediaSrcFor(filePath) {
  return `media://${encodeURIComponent(filePath)}`;
}

export class PlaybackEngine {
  constructor({ audio, bridge } = {}) {
    this.audio = audio || (typeof Audio !== 'undefined' ? new Audio() : null);
    this.bridge = bridge || (typeof window !== 'undefined' ? window.freeplayer : null);
    this._listeners = new Set();
    this._bound = false;
    this._lastSecond = -1;

    // Session + accounting state
    this._sessionId = null;
    this._playedMs = 0;
    this._segmentStart = null;   // wall clock when the current play segment began
    this._maxPosition = 0;
    this._lastKnownPosition = 0;
    this._trackId = null;
  }

  // ── events ──

  subscribe(listener) {
    this._listeners.add(listener);
    return () => this._listeners.delete(listener);
  }

  _emit(type, payload) {
    for (const listener of this._listeners) {
      try {
        listener(type, payload);
      } catch (err) {
        console.error('PlaybackEngine listener failed:', err);
      }
    }
  }

  // ── element wiring ──

  // Idempotent: binds the element's media events once. Safe to call after a
  // remount — the engine outlives the UI layer.
  bind() {
    const audio = this.audio;
    if (!audio || this._bound) return;
    this._bound = true;

    this._handlers = {
      timeupdate: () => {
        const t = audio.currentTime || 0;
        this._notePosition(t);
        const whole = Math.floor(t);
        if (whole !== this._lastSecond) {
          this._lastSecond = whole;
          this._emit('timeupdate', t);
        }
      },
      durationchange: () => this._emit('durationchange', audio.duration || 0),
      ended: () => {
        this._closeSegment();
        this._emit('ended', null);
      },
      play: () => {
        // The graph must exist on every play path, including ones that bypass
        // the UI (repeat-one, media keys, other windows).
        audioEngine.connect(audio);
        audioEngine.resume();
        if (this._segmentStart == null) this._segmentStart = Date.now();
        this._emit('playing', true);
      },
      pause: () => {
        this._closeSegment();
        this._emit('playing', false);
      },
      error: () => {
        const err = audio.error;
        this._emit('error', {
          code: err?.code,
          name: MEDIA_ERROR_CODES[err?.code] || 'UNKNOWN',
          message: err?.message || '',
          src: audio.src,
        });
      },
    };

    audio.addEventListener('timeupdate', this._handlers.timeupdate);
    audio.addEventListener('durationchange', this._handlers.durationchange);
    audio.addEventListener('ended', this._handlers.ended);
    audio.addEventListener('play', this._handlers.play);
    audio.addEventListener('pause', this._handlers.pause);
    audio.addEventListener('error', this._handlers.error);
    this._mediaStateEvents = ['loadedmetadata', 'canplay', 'playing', 'stalled', 'waiting', 'abort', 'emptied', 'suspend'];
    this._handlers.mediaState = (event) => this._emit('mediastate', {
      type: event.type,
      src: audio.src,
      readyState: audio.readyState,
      networkState: audio.networkState,
      currentTime: audio.currentTime,
      duration: audio.duration,
    });
    for (const name of this._mediaStateEvents) audio.addEventListener(name, this._handlers.mediaState);
  }

  unbind() {
    const audio = this.audio;
    if (!audio || !this._bound) return;
    for (const name of ['timeupdate', 'durationchange', 'ended', 'play', 'pause', 'error']) {
      audio.removeEventListener(name, this._handlers[name]);
    }
    for (const name of this._mediaStateEvents) audio.removeEventListener(name, this._handlers.mediaState);
    this._bound = false;
  }

  // ── playback ──

  // Point the element at a track and start it. Resolves once playback started
  // and the session exists; rejects with the underlying play() error otherwise
  // (the caller decides whether that is fatal — a session is never opened for a
  // track that failed to start).
  async play(track) {
    const audio = this.audio;
    if (!audio || !track) return false;

    const id = track.id ?? null;
    // A repeat of the SAME track still ends the previous session first: one
    // looping track used to be reported as a single session that grew forever
    // (an hour of looping = one play_history row), because the old repeat path
    // only rewound the element.
    if (this._sessionId != null) {
      try {
        await this.closeSession();
      } catch (err) {
        console.error('Failed to end play session:', err);
      }
    }
    this._trackId = id;
    this._lastSecond = -1;
    this._maxPosition = 0;
    this._lastKnownPosition = 0;

    audio.src = mediaSrcFor(track.file_path);
    audioEngine.setGain(track.replaygain_gain || 0);
    // Wire the graph before play(): the EQ must be in the playback path in every
    // view, and re-routing a playing element mid-flight audibly hiccups.
    audioEngine.connect(audio);
    audioEngine.resume();

    await audio.play();
    await this.openSession(id);
    return true;
  }

  pause() {
    this.audio?.pause();
  }

  resume() {
    if (!this.audio) return;
    audioEngine.resume();
    this.audio.play().catch((err) => this._emit('error', { name: 'PLAY_REJECTED', message: String(err?.message || err) }));
  }

  seek(time) {
    if (!this.audio) return;
    const t = Math.max(0, Number(time) || 0);
    this.audio.currentTime = t;
    this._notePosition(t);
  }

  setVolume(v) {
    if (this.audio) this.audio.volume = v;
    audioEngine.setVolume(v);
  }

  setReplayGain(db) {
    audioEngine.setGain(db || 0);
  }

  get paused() {
    return this.audio ? this.audio.paused : true;
  }

  get currentTime() {
    return this.audio?.currentTime || 0;
  }

  get duration() {
    return this.audio?.duration || 0;
  }

  // ── sessions & accounting ──

  _notePosition(t) {
    if (t > this._maxPosition) this._maxPosition = t;
    this._lastKnownPosition = t;
  }

  // Fold the elapsed wall clock of the current play segment into playedMs.
  // Called on every transition that stops playback.
  _closeSegment() {
    if (this._segmentStart == null) return;
    this._playedMs += Date.now() - this._segmentStart;
    this._segmentStart = null;
    this._notePosition(this.audio?.currentTime || this._lastKnownPosition);
  }

  async openSession(trackId) {
    if (!this.bridge?.playStart) return null;
    this._closeSegment();
    this._playedMs = 0;
    this._segmentStart = Date.now();
    const id = await this.bridge.playStart(trackId);
    this._sessionId = id ?? null;
    return this._sessionId;
  }

  // What the session should be recorded as, derived from played position rather
  // than wall clock. Returns null when there is nothing to close.
  sessionSnapshot() {
    const startedAt = this._segmentStart;
    const playedMs = this._playedMs + (startedAt != null ? Date.now() - startedAt : 0);
    const duration = this.duration;
    const percentage = duration > 0 ? Math.min((this._maxPosition / duration) * 100, 100) : 0;
    return {
      sessionId: this._sessionId,
      durationSeconds: Math.round(playedMs / 1000),
      playPercentage: Math.round(percentage),
    };
  }

  // Ends the open session (if any) and clears the accounting state.
  async closeSession() {
    const snapshot = this.sessionSnapshot();
    this._sessionId = null;
    this._playedMs = 0;
    this._segmentStart = null;
    this._maxPosition = 0;
    this._lastKnownPosition = 0;
    if (!snapshot.sessionId || !this.bridge?.playEnd) return null;
    await this.bridge.playEnd(snapshot);
    return snapshot;
  }

  // Drop session + accounting state WITHOUT reporting it. Used when switching to
  // a different track: the previous session is closed by closeSession() first.
  resetSession() {
    this._closeSegment();
    this._sessionId = null;
    this._playedMs = 0;
    this._segmentStart = null;
    this._maxPosition = 0;
    this._lastKnownPosition = 0;
  }

  get trackId() {
    return this._trackId;
  }

  setTrackId(id) {
    this._trackId = id;
  }

  dispose() {
    this.unbind();
    audioEngine.dispose();
  }

  // Called when the UI layer unmounts. Reports the open session so an ended
  // session is never lost, but leaves the engine (and the audio graph) intact:
  // it is a process-lifetime singleton and a remount must not lose playback.
  async closeSessionOnUnmount() {
    this._closeSegment();
    if (this._sessionId == null) return null;
    const snapshot = this.sessionSnapshot();
    this._sessionId = null;
    this._playedMs = 0;
    this._segmentStart = null;
    if (!this.bridge?.playEnd) return snapshot;
    await this.bridge.playEnd(snapshot);
    return snapshot;
  }
}

// The app runs one engine for the lifetime of the process; the UI layer may
// unmount and remount around it (StrictMode, HMR, window switches) without
// losing the audio element or an in-flight session.
let shared = null;

export function getPlaybackEngine() {
  if (!shared) shared = new PlaybackEngine();
  return shared;
}

export function __setPlaybackEngineForTests(engine) {
  shared = engine;
}
