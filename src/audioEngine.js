// ── Module-level audio graph (persists across mount/unmount cycles) ──
// Moved to a separate file because Vite Fast Refresh breaks when a React
// component file has named exports alongside the default export.

let audioCtx = null;
let analyser = null;
let gainNode = null;
let sourceNode = null;
let connectedElement = null;
let pendingGainDb = 0;

export function ensureAudioGraph(audioElement) {
  if (!audioElement) return null;
  if (connectedElement === audioElement && analyser) return analyser;

  try {
    if (!audioCtx || audioCtx.state === 'closed') {
      audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    }
    if (!analyser) {
      analyser = audioCtx.createAnalyser();
      analyser.fftSize = 2048;
      analyser.smoothingTimeConstant = 0.65;
      analyser.minDecibels = -90;
      analyser.maxDecibels = -10;
    }
    if (!gainNode) {
      gainNode = audioCtx.createGain();
      gainNode.gain.value = Math.pow(10, pendingGainDb / 20);
    }
    if (connectedElement !== audioElement) {
      sourceNode = audioCtx.createMediaElementSource(audioElement);
      sourceNode.connect(analyser);
      analyser.connect(gainNode);
      gainNode.connect(audioCtx.destination);
      connectedElement = audioElement;
    }
    return analyser;
  } catch (err) {
    console.warn('Audio graph wiring failed:', err.message);
    analyser = null;
    connectedElement = null;
    return null;
  }
}

export function resumeAudioContext() {
  if (audioCtx?.state === 'suspended') audioCtx.resume();
}

export function setPlaybackGain(gainDb) {
  pendingGainDb = gainDb;
  if (!gainNode || !audioCtx) return;
  const targetGain = Math.pow(10, gainDb / 20);
  const now = audioCtx.currentTime;
  gainNode.gain.cancelScheduledValues(now);
  gainNode.gain.setTargetAtTime(targetGain, now, 0.05);
}
