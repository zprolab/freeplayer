// AudioEngine — manages Web Audio API graph lifecycle
// Single instance per app; survives React remount

export class AudioEngine {
  constructor() {
    this.ctx = null;
    this.analyser = null;
    this.gainNode = null;
    this.sourceNode = null;
    this.connectedElement = null;
    this._pendingGainDb = 0;
  }

  connect(audioElement) {
    if (!audioElement) return null;
    if (this.connectedElement === audioElement && this.analyser) {
      return this.analyser;
    }

    try {
      if (!this.ctx || this.ctx.state === 'closed') {
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
        this.gainNode.gain.value = Math.pow(10, this._pendingGainDb / 20);
      }
      if (this.connectedElement !== audioElement) {
        this.sourceNode = this.ctx.createMediaElementSource(audioElement);
        this.sourceNode.connect(this.analyser);
        this.analyser.connect(this.gainNode);
        this.gainNode.connect(this.ctx.destination);
        this.connectedElement = audioElement;
      }
      return this.analyser;
    } catch (err) {
      console.warn('Audio graph wiring failed:', err.message);
      this.analyser = null;
      this.connectedElement = null;
      return null;
    }
  }

  resume() {
    if (this.ctx?.state === 'suspended') {
      this.ctx.resume();
    }
  }

  setGain(gainDb) {
    this._pendingGainDb = gainDb;
    if (!this.gainNode || !this.ctx) return;
    const targetGain = Math.pow(10, gainDb / 20);
    const now = this.ctx.currentTime;
    this.gainNode.gain.cancelScheduledValues(now);
    this.gainNode.gain.setTargetAtTime(targetGain, now, 0.05);
  }

  dispose() {
    if (this.sourceNode) {
      try { this.sourceNode.disconnect(); } catch {}
      this.sourceNode = null;
    }
    if (this.analyser) {
      try { this.analyser.disconnect(); } catch {}
      this.analyser = null;
    }
    if (this.gainNode) {
      try { this.gainNode.disconnect(); } catch {}
      this.gainNode = null;
    }
    if (this.ctx && this.ctx.state !== 'closed') {
      this.ctx.close();
    }
    this.ctx = null;
    this.connectedElement = null;
  }
}

// Singleton — one audio graph for the app lifetime
export const audioEngine = new AudioEngine();
