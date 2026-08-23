// Mono font preference — the app NEVER loads fonts from the network; the
// default CSS stack (--font-mono) resolves against fonts installed locally,
// and the user can pin a specific family via Settings > Appearance.
// The renderer (canvas labels in the visualizer) reads the active family
// from here instead of hardcoding a name.

let currentMono = '';

export function applyMonoFont(family) {
  const f = typeof family === 'string' && family.trim() ? family.trim() : '';
  currentMono = f;
  if (typeof document !== 'undefined' && document.documentElement) {
    document.documentElement.style.setProperty('--font-mono', f || '');
  }
}

// Returns the active family quoted for canvas font strings
// (multi-word names need quotes), falling back to `monospace`.
export function monoFontStack() {
  return currentMono ? `"${currentMono}"` : 'monospace';
}
