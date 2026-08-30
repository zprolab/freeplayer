import { useCallback, useEffect, useRef } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { audioEngine } from '../audio/audioEngine';
import { computeNextIndex, computePrevIndex, shuffleArray } from './playQueue';

export function usePlayback() {
  const { state, dispatch, audioRef, playSessionIdRef, playStartTimeRef } = usePlayer();

  // Close the session currently open. Refs are cleared BEFORE the playEnd
  // round-trip so a concurrent transition can never read the same session
  // twice — that would skip one playEnd and leak an ended_at NULL row into
  // the stats table.
  const endPlaySession = useCallback(async () => {
    const prevSid = playSessionIdRef.current;
    const prevStart = playStartTimeRef.current;
    if (!prevSid || !prevStart) return;
    playSessionIdRef.current = null;
    playStartTimeRef.current = null;
    const elapsed = (Date.now() - prevStart) / 1000;
    const trackDuration = audioRef.current.duration || 0;
    const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
    try {
      await window.freeplayer.playEnd({
        sessionId: prevSid,
        durationSeconds: Math.round(elapsed),
        playPercentage: Math.round(percentage),
      });
    } catch (err) {
      console.error('Failed to end play session:', err);
    }
  }, [audioRef, playSessionIdRef, playStartTimeRef]);

  // Serializes session transitions: every playTrack queues behind the one
  // before it, so rapid calls each end the session the previous one left
  // (a rejected chain is reset by the .catch below, never shared onward).
  const sessionTransitionRef = useRef(Promise.resolve());

  const playTrack = useCallback(async (track) => {
    const transition = sessionTransitionRef.current
      .catch(() => {})
      .then(async () => {
        // End the previous session BEFORE attempting playback: a play()
        // rejection must never leave the old session unclosed.
        await endPlaySession();
        dispatch({ type: 'SET_CURRENT_TRACK', payload: track });
        // Encode the complete path. encodeURI leaves '#' and '?' unescaped,
        // which WebKit interprets as URL fragment/query and truncates filenames.
        audioRef.current.src = `media://${encodeURIComponent(track.file_path)}`;
        const gainDb = track.replaygain_gain || 0;
        audioEngine.setGain(gainDb);
        try {
          await audioRef.current.play();
          const sessionId = await window.freeplayer.playStart(track.id);
          playSessionIdRef.current = sessionId;
          playStartTimeRef.current = Date.now();
        } catch (err) {
          console.error('Playback failed:', err);
        }
      });
    sessionTransitionRef.current = transition;
    try {
      await transition;
    } catch (err) {
      console.error('Playback transition failed:', err);
    }
  }, [dispatch, audioRef, endPlaySession]);

  const togglePlayPause = useCallback(() => {
    const audio = audioRef.current;
    if (!audio.src && state.tracks.length > 0) {
      playTrack(state.tracks[0]);
      return;
    }
    if (audio.paused) {
      audio.play().catch(console.error);
    } else {
      audio.pause();
    }
  }, [audioRef, state.tracks, playTrack]);

  const handleNext = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
    if (!queue.length) return;

    if (playMode === 'repeat-one') {
      audioRef.current.currentTime = 0;
      audioRef.current.play().catch(console.error);
      return;
    }

    const { nextIdx, reshuffled } = computeNextIndex({ queue, queueIndex, playMode, shuffledQueue });
    if (nextIdx < 0) return; // queue no longer contains the target — skip
    if (reshuffled) dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: reshuffled });
    dispatch({ type: 'SET_QUEUE_INDEX', payload: nextIdx });
    playTrack(queue[nextIdx]);
  }, [state, audioRef, dispatch, playTrack]);

  const handlePrev = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
    if (!queue.length) return;

    const { prevIdx } = computePrevIndex({
      queue, queueIndex, currentTime: audioRef.current.currentTime, playMode, shuffledQueue,
    });
    if (prevIdx === queueIndex) {
      // More than 3s in — restart the current track instead of stepping back
      audioRef.current.currentTime = 0;
      return;
    }
    if (prevIdx < 0) return;
    dispatch({ type: 'SET_QUEUE_INDEX', payload: prevIdx });
    playTrack(queue[prevIdx]);
  }, [state, audioRef, dispatch, playTrack]);

  const handleSeek = useCallback((time) => {
    audioRef.current.currentTime = time;
    dispatch({ type: 'SET', payload: { currentTime: time } });
  }, [audioRef, dispatch]);

  const handleVolumeChange = useCallback((vol) => {
    // Reject junk input before it reaches the engine gain node or the DB
    // (NaN would persist String(NaN) and poison the graph gain).
    if (!Number.isFinite(vol)) return;
    const v = Math.min(Math.max(vol, 0), 1);
    audioRef.current.volume = v;
    // Element volume is the fallback; once the Web Audio graph is connected
    // (Now Playing visualizer) WebKit ignores it, so the engine's gain node
    // carries the user volume from then on.
    audioEngine.setVolume(v);
    dispatch({ type: 'SET_VOLUME', payload: v });
    // Persist globally so volume survives restarts (shared by all views)
    window.freeplayer.setSetting({ key: 'volume', value: String(v) })
      .catch(() => {});
  }, [audioRef, dispatch]);

  const playTrackFromList = useCallback(async (track, trackList) => {
    dispatch({ type: 'SET_QUEUE', payload: trackList });
    const idx = trackList.findIndex(t => t.id === track.id);
    dispatch({ type: 'SET_QUEUE_INDEX', payload: idx });

    if (state.playMode === 'shuffle') {
      const shuffled = shuffleArray(trackList);
      const clickedIdx = shuffled.findIndex(t => t.id === track.id);
      if (clickedIdx > 0) {
        [shuffled[0], shuffled[clickedIdx]] = [shuffled[clickedIdx], shuffled[0]];
      }
      dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: shuffled });
    }

    await playTrack(track);
  }, [dispatch, state.playMode, playTrack]);

  // Latest playback handlers behind a ref so the listeners below register
  // once with stable deps — handleNext/handlePrev/togglePlayPause are rebuilt
  // on every state change, and depending on them directly would tear down and
  // re-add the audio listeners every second during playback.
  const playHandlersRef = useRef({ togglePlayPause, handleNext, handlePrev });
  playHandlersRef.current = { togglePlayPause, handleNext, handlePrev };

  // Audio element event listeners (no longer tied to volume changes)
  useEffect(() => {
    const audio = audioRef.current;
    // P1: throttle time updates to whole seconds — timeupdate fires ~4Hz and
    // each dispatch re-renders the whole tree; second-granularity is plenty
    // for the progress bar
    let lastSecond = -1;

    const onTimeUpdate = () => {
      const t = audio.currentTime;
      const s = Math.floor(t);
      if (s !== lastSecond) {
        lastSecond = s;
        dispatch({ type: 'SET', payload: { currentTime: t } });
      }
    };
    const onDurationChange = () => dispatch({ type: 'SET', payload: { duration: audio.duration || 0 } });
    const onEnded = () => playHandlersRef.current.handleNext();
    const onPlay = () => dispatch({ type: 'SET_IS_PLAYING', payload: true });
    const onPause = () => dispatch({ type: 'SET_IS_PLAYING', payload: false });
    const onError = () => {
      const err = audio.error;
      const codes = { 1: 'MEDIA_ERR_ABORTED', 2: 'MEDIA_ERR_NETWORK', 3: 'MEDIA_ERR_DECODE', 4: 'MEDIA_ERR_SRC_NOT_SUPPORTED' };
      console.error('Audio error:', codes[err?.code] || 'UNKNOWN', err?.message || '', 'src:', audio.src);
      window.freeplayer?.logDiagnostic?.('playback', 'error', `Audio error: ${JSON.stringify({ code: err?.code, name: codes[err?.code] || 'UNKNOWN', message: err?.message || '', src: audio.src, readyState: audio.readyState, networkState: audio.networkState })}`);
    };
    const onMediaState = (event) => {
      window.freeplayer?.logDiagnostic?.('playback', 'info', `Media event ${event.type}: ${JSON.stringify({ src: audio.src, readyState: audio.readyState, networkState: audio.networkState, currentTime: audio.currentTime, duration: audio.duration })}`);
    };

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('durationchange', onDurationChange);
    audio.addEventListener('ended', onEnded);
    audio.addEventListener('play', onPlay);
    audio.addEventListener('pause', onPause);
    audio.addEventListener('error', onError);
    ['loadedmetadata', 'canplay', 'playing', 'stalled', 'waiting', 'abort', 'emptied', 'suspend'].forEach((name) => audio.addEventListener(name, onMediaState));

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('durationchange', onDurationChange);
      audio.removeEventListener('ended', onEnded);
      audio.removeEventListener('play', onPlay);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('error', onError);
      ['loadedmetadata', 'canplay', 'playing', 'stalled', 'waiting', 'abort', 'emptied', 'suspend'].forEach((name) => audio.removeEventListener(name, onMediaState));
    };
  }, [audioRef, dispatch]);

  // Separate volume effect — no longer tears down event listeners
  useEffect(() => {
    audioRef.current.volume = state.volume;
    audioEngine.setVolume(state.volume);
  }, [state.volume, audioRef]);

  // End play session on unmount. Waits for any in-flight transition first so
  // the session it just opened is closed too; playEnd is awaited/caught so a
  // rejection can't leave the row unclosed. audioEngine.dispose() is
  // idempotent, so StrictMode/HMR remounts leave the singleton usable.
  useEffect(() => {
    return () => {
      (async () => {
        const chain = sessionTransitionRef.current;
        try { await chain; } catch {}
        const sid = playSessionIdRef.current;
        if (!sid || !playStartTimeRef.current) return;
        const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
        const trackDuration = audioRef.current.duration || 0;
        const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
        try {
          await window.freeplayer.playEnd({
            sessionId: sid,
            durationSeconds: Math.round(elapsed),
            playPercentage: Math.round(percentage),
          });
        } catch (err) {
          console.error('Failed to end play session on unmount:', err);
        }
      })();
      audioEngine.dispose();
    };
  }, [audioRef, playSessionIdRef, playStartTimeRef, sessionTransitionRef]);

  // Push playback state to main process for tray menu. The native side only
  // reads isPlaying (shell/src/bridge.mm sendPlaybackState), so re-sending on
  // track change carries no information — fire on isPlaying only.
  useEffect(() => {
    window.freeplayer?.sendPlaybackState(state.isPlaying);
  }, [state.isPlaying]);

  // System media key support — registered once, dispatching through the ref
  // so the latest handlers are always used. onMediaKey stores a single global
  // handler (bridge.mm), so unmount re-registers a no-op instead of leaving a
  // stale handler dispatching into unmounted state.
  useEffect(() => {
    if (!window.freeplayer.onMediaKey) return;
    const handler = (action) => {
      const h = playHandlersRef.current;
      switch (action) {
        case 'playpause': h.togglePlayPause(); break;
        case 'next': h.handleNext(); break;
        case 'previous': h.handlePrev(); break;
      }
    };
    window.freeplayer.onMediaKey(handler);
    return () => {
      window.freeplayer.onMediaKey(() => {});
    };
  }, []);

  return {
    playTrack,
    togglePlayPause,
    handleNext,
    handlePrev,
    handleSeek,
    handleVolumeChange,
    playTrackFromList,
  };
}
