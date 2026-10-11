// Ambient palette for immersive mode.
//
// The background is derived from the cover art (an 8×8 average), but the fixed
// brand red was NOT: it sat on top of that teal as a complementary pair, which
// reads as "dirty" rather than deliberate — near-complementary saturated colours
// vibrate against each other.
//
// Measured on a real cover (Ed Sheeran / Celestial — teal artwork, so the
// average is teal): the brand red #e24329 reaches only 3.32:1 on the tinted
// background, because red contributes little to relative luminance. Its long
// wavelength is exactly why it looks muddy on a teal field.
//
// So the accent is DERIVED from the same source colour as the background:
// rotate the cover's hue into the warm half of the wheel and raise its
// lightness until it is comfortably readable. A teal cover (182°) lands at 32° —
// amber, still the warm family the brand lives in, but at 7.46:1 instead of
// 3.32:1. A warm cover keeps a warm accent; the hue is never forced to a fixed
// value.
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

/**
 * The readable accent for an ambient background colour.
 *
 * Two rules, in order:
 *  1. A COOL cover is rotated into the warm half of the wheel, so the accent
 *     never lands on the background's own complement (that pairing is what reads
 *     as dirty). Teal (182°) lands at 32° — amber.
 *  2. A WARM cover keeps its own hue, merely brightened. A fixed +210° rotation
 *     is wrong here: an orange cover (22°) would land at 232°, i.e. blue, so the
 *     accent would contradict the artwork it came from. The hue is derived, not
 *     forced — that is the whole point of deriving it.
 *
 * Lightness is what actually buys readability: red contributes little to
 * relative luminance, which is why the brand red reached only 3.32:1 on a dark
 * cover-derived background no matter how it was paired.
 */
export function accentFor(color, { warmTarget = 32, saturation = 0.85, lightness = 0.68 } = {}) {
  if (!color) return null;
  const { h } = rgbToHsl(color.r, color.g, color.b);
  const isWarm = h < 90 || h > 330;
  const hue = isWarm ? h : warmTarget;
  const [r, g, b] = hslToRgb(hue, saturation, lightness);
  return { r, g, b };
}

/** `rgb(r, g, b)` for inline styles. */
export const cssRgb = (c) => (c ? `rgb(${c.r}, ${c.g}, ${c.b})` : undefined);
