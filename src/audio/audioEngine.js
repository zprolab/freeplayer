// AudioEngine — manages Web Audio API graph lifecycle
// Single instance per app; survives React remount

import { EQ_BANDS } from './eqPresets';

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.analyser = null;
    this.gainNode = null;
    this.sourceNode = null;
    this.eqFilters = null;
    this.connectedElement = null;
    this._pendingGainDb = 0;
    this._pendingVolume = 1;
    this._resumeRetrying = false;
    // WKWebView/Safari freeze the AudioContext without a user gesture;
    // any interaction unlocks it so late-mounted visualizers get data.
    this._unlock = () => this.resume();
    if (typeof document !== 'undefined') {
      document.addEventListener('pointerdown', this._unlock);
      document.addEventListener('keydown', this._unlock);
    }
  }

  // Disconnect and drop every node. Nodes built on a closed AudioContext are
  // dead and throw on connect(), so a context rebuild must never reuse them.
  _resetGraph() {
    if (this.sourceNode) {
      try { this.sourceNode.disconnect(); } catch {}
    }
    if (this.analyser) {
      try { this.analyser.disconnect(); } catch {}
    }
    if (this.gainNode) {
      try { this.gainNode.disconnect(); } catch {}
    }
    if (this.eqFilters) {
      this.eqFilters.forEach((f) => { try { f.disconnect(); } catch {} });
    }
    this.sourceNode = null;
    this.analyser = null;
    this.gainNode = null;
    this.eqFilters = null;
    this.connectedElement = null;
  }

  connect(audioElement) {
    if (!audioElement) return null;
    if (this.ctx && this.ctx.state !== 'closed'
      && this.connectedElement === audioElement && this.analyser) {
      return this.analyser;
    }

    try {
      if (!this.ctx || this.ctx.state === 'closed') {
        // Dead context: every node built on it is dead too. Reset the whole
        // graph — a stale sourceNode would also make the next
        // createMediaElementSource on the same element throw InvalidStateError.
        this._resetGraph();
        this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      }
      if (!this.analyser) {
        this.analyser = this.ctx.createAnalyser();
        this.analyser.fftSize = 2048;
        this.analyser.smoothingTimeConstant = 0.65;
        this.analyser.minDecibels = -90;
        this.analyser.maxDecibels = -10;
      }
      if (!this.gainNode) {
        this.gainNode = this.ctx.createGain();
        // User volume AND replaygain are both applied here: once the
        // element is routed through the graph (WebKit ignores the
        // element's own volume/mute in that case), this node is the
        // single volume authority, so it must start at exactly the
        // effective volume the user had before the graph connected.
        this.gainNode.gain.value = this._pendingVolume * Math.pow(10, this._pendingGainDb / 20);
      }
      if (!this.eqFilters) {
        this.eqFilters = EQ_BANDS.map((freq) => {
          const f = this.ctx.createBiquadFilter();
          f.type = 'peaking';
          f.frequency.value = freq;
          f.Q.value = 1.4142;
          return f;
        });
        // Restore a curve that was applied before the graph existed
        // (startup or AudioContext rebuild) — mirrors setGain's pending pattern.
        if (this._pendingEqGains) this._applyTargets(this.ctx.currentTime);
      }
      if (this.connectedElement !== audioElement) {
        // Detach the previous element's source first: keeping it wired would
        // leave the old element feeding the analyser alongside the new one.
        if (this.sourceNode) {
          try { this.sourceNode.disconnect(); } catch {}
        }
        this.sourceNode = this.ctx.createMediaElementSource(audioElement);
        // From here on the element output flows through this graph, where
        // its own volume/mute attributes no longer apply (WKWebView).
        // Normalize it so the graph gain node is the only volume control
        // and volume can never be double-applied.
        audioElement.volume = 1;
        this.sourceNode.connect(this.eqFilters[0]);
        for (let i = 1; i < this.eqFilters.length; i++) {
          this.eqFilters[i - 1].connect(this.eqFilters[i]);
        }
        // Analyser sits AFTER the EQ chain so the visualizer shows the
        // spectrum the user actually hears, EQ included.
        this.eqFilters[this.eqFilters.length - 1].connect(this.analyser);
        this.analyser.connect(this.gainNode);
        this.gainNode.connect(this.ctx.destination);
        this.connectedElement = audioElement;
      }
      // Late graph wiring (e.g. visualizer mounted after playback started)
      // must not leave the context suspended — that freezes the analyser
      // AND silences the element routed through it.
      this.resume();
      return this.analyser;
    } catch (err) {
      console.warn('Audio graph wiring failed:', err.message);
      // A dangling sourceNode makes the next createMediaElementSource on the
      // same element throw InvalidStateError — reset the whole graph so a
      // retry starts from a clean slate.
      this._resetGraph();
      return null;
    }
  }

  resume() {
    if (!this.ctx || this.ctx.state === 'closed' || this.ctx.state === 'running') return;
    // One in-flight retry chain at a time — concurrent resume() calls must
    // not each spawn their own loop.
    if (this._resumeRetrying) return;
    this._resumeRetrying = true;
    const MAX_RETRIES = 20;
    let attempts = 0;
    const scheduleRetry = () => setTimeout(tryOnce, 250);
    const tryOnce = () => {
      if (!this.ctx || this.ctx.state === 'closed' || this.ctx.state === 'running') {
        this._resumeRetrying = false;
        return;
      }
      if (attempts >= MAX_RETRIES) {
        // Give up quietly — the next interaction triggers a fresh resume().
        this._resumeRetrying = false;
        return;
      }
      attempts++;
      try {
        this.ctx.resume().then(() => {
          if (this.ctx && this.ctx.state === 'suspended') {
            scheduleRetry();
          } else {
            this._resumeRetrying = false;
          }
        }).catch(() => scheduleRetry());
      } catch {
        scheduleRetry();
      }
    };
    tryOnce();
  }

  setGain(gainDb) {
    this._pendingGainDb = gainDb;
    // A closed context throws on currentTime/gain access — record the pending
    // value and stay quiet until the graph is rebuilt.
    if (!this.gainNode || !this.ctx || this.ctx.state === 'closed') return;
    const targetGain = this._pendingVolume * Math.pow(10, gainDb / 20);
    const now = this.ctx.currentTime;
    this.gainNode.gain.cancelScheduledValues(now);
    this.gainNode.gain.setTargetAtTime(targetGain, now, 0.05);
  }

  // User volume. While the element is routed through the graph this is the
  // only effective volume control (the element's own volume is ignored by
  // WebKit once a MediaElementSource exists), so it is applied here in
  // addition to the element fallback used before the graph connects.
  setVolume(volume) {
    // NaN/Infinity would poison the gain value and the pending restore.
    if (!Number.isFinite(volume)) return;
    this._pendingVolume = Math.min(Math.max(volume, 0), 1);
    if (!this.gainNode || !this.ctx || this.ctx.state === 'closed') return;
    const targetGain = this._pendingVolume * Math.pow(10, this._pendingGainDb / 20);
    const now = this.ctx.currentTime;
    this.gainNode.gain.cancelScheduledValues(now);
    this.gainNode.gain.setTargetAtTime(targetGain, now, 0.02);
  }

  applyEq(gains, enabled = true) {
    this._pendingEqGains = gains;
    this._pendingEqEnabled = enabled;
    if (!this.eqFilters || !this.ctx || this.ctx.state === 'closed') return;
    this._applyTargets(this.ctx.currentTime);
  }

  _applyTargets(now) {
    if (!this.eqFilters || !this.ctx || this.ctx.state === 'closed' || !this._pendingEqGains) return;
    const targets = this._pendingEqEnabled ? this._pendingEqGains : this._pendingEqGains.map(() => 0);
    this.eqFilters.forEach((f, i) => {
      const t = Math.min(Math.max(targets[i] ?? 0, -12), 12);
      f.gain.cancelScheduledValues(now);
      f.gain.setTargetAtTime(t, now, 0.05);
    });
  }

  dispose() {
    this._resetGraph();
    this._resumeRetrying = false;
    if (this.ctx && this.ctx.state !== 'closed') {
      try { this.ctx.close(); } catch {}
    }
    this.ctx = null;
    // Idempotent and safe to call on an app-lifetime singleton (StrictMode /
    // HMR remounts): later setGain/setVolume/applyEq calls record pending
    // values and no-op until connect() rebuilds the graph.
    if (typeof document !== 'undefined') {
      document.removeEventListener('pointerdown', this._unlock);
      document.removeEventListener('keydown', this._unlock);
    }
  }
}

// Singleton — one audio graph for the app lifetime
export const audioEngine = new AudioEngine();
