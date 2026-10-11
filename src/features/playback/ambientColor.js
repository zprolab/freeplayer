// Ambient palette for immersive mode.
//
// The background is derived from the cover art (an 8×8 average). The accent used
// to be the fixed brand red, which on a teal cover sat on its own complement —
// near-complementary saturated colours vibrate against each other, and that is
// what read as "dirty" rather than deliberate.
//
// So the accent now comes from the same source as the background, by two simple
// rules:
//
//   1. HUE — the cover's own hue. A cool cover is pulled into the warm half of
//      the wheel so the accent never lands on the field's complement (teal 182°
//      → 32° amber); a warm cover keeps its hue, so the accent never contradicts
//      the artwork it came from.
//   2. LIGHTNESS — two fixed steps, inverted against the field: dark field →
//      light accent, light field → dark accent.
//
// Deliberately simple, and worth recording why: an earlier version of this file
// searched for the maximum WCAG contrast and converged on rgb(252,236,217) for a
// teal cover — effectively white, i.e. no accent at all. Two fixed steps keep the
// hue recognisable, which is the actual goal of a colour derived from artwork.
//
// Pure functions, no DOM: the maths is testable even though the look is not.

/** sRGB (0-255 per channel) -> HSL with h in [0,360), s and l in [0,1]. */
export function rgbToHsl(r, g, b) {
  const rn = r / 255;
  const gn = g / 255;
  const bn = b / 255;
  const max = Math.max(rn, gn, bn);
  const min = Math.min(rn, gn, bn);
  const l = (max + min) / 2;
  const d = max - min;
  if (d === 0) return { h: 0, s: 0, l };
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
  let h;
  if (max === rn) h = ((gn - bn) / d) % 6;
  else if (max === gn) h = (bn - rn) / d + 2;
  else h = (rn - gn) / d + 4;
  h *= 60;
  if (h < 0) h += 360;
  return { h, s, l };
}

/** HSL -> sRGB (0-255 per channel). */
export function hslToRgb(h, s, l) {
  const c = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = c * (1 - Math.abs((hp % 2) - 1));
  let rgb;
  if (hp < 1) rgb = [c, x, 0];
  else if (hp < 2) rgb = [x, c, 0];
  else if (hp < 3) rgb = [0, c, x];
  else if (hp < 4) rgb = [0, x, c];
  else if (hp < 5) rgb = [x, 0, c];
  else rgb = [c, 0, x];
  const m = l - c / 2;
  return rgb.map((v) => Math.round((v + m) * 255));
}

/** WCAG relative luminance — used only to decide which side of the field to sit on. */
export function relativeLuminance({ r, g, b }) {
  const chan = (c) => {
    const v = c / 255;
    return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b);
}

/** WCAG contrast ratio, for tests and for checking a palette choice. */
export function contrastRatio(a, b) {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/**
 * The accent for the immersive view, derived from the ambient colour.
 *
 * `warmTarget` is the hue a cool cover is brought to. `saturation` is high enough
 * that the result always reads as a colour rather than a grey.
 */
export function accentFor(color, { warmTarget = 32, saturation = 0.8 } = {}) {
  if (!color) return null;
  const { h } = rgbToHsl(color.r, color.g, color.b);
  const isWarm = h < 90 || h > 330;
  const hue = isWarm ? h : warmTarget;
  // Inverted against the field: a dark ambient field gets the light step, a light
  // one gets the dark step.
  const lightness = relativeLuminance(color) > 0.5 ? 0.42 : 0.68;
  const [r, g, b] = hslToRgb(hue, saturation, lightness);
  return { r, g, b };
}

/** `rgb(r, g, b)` for inline styles; undefined lets the CSS fallback apply. */
export const cssRgb = (c) => (c ? `rgb(${c.r}, ${c.g}, ${c.b})` : undefined);
