// The immersive accent is derived from the cover's average colour so the
// highlight belongs to the artwork. The LOOK cannot be asserted here — but the
// maths can, and the maths is where the previous version went wrong: a fixed
// brand red reached only 3.32:1 on a cover-derived background while sitting on
// its own complement, which is what read as "dirty" rather than deliberate.
import { describe, it, expect } from 'vitest';
import { rgbToHsl, hslToRgb, accentFor, cssRgb } from '@/features/playback/ambientColor.js';

// WCAG relative luminance / contrast, so the readability claim is measured
// rather than eyeballed.
const chan = (c) => {
  const v = c / 255;
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
};
const lum = ({ r, g, b }) => 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b);
const ratio = (a, b) => {
  const la = lum(a); const lb = lum(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
};
/** The ambient background as rendered: the 0.42 dark tint over the average. */
const tinted = (c, alpha = 0.42) => ({
  r: Math.round(10 * alpha + c.r * (1 - alpha)),
  g: Math.round(10 * alpha + c.g * (1 - alpha)),
  b: Math.round(13 * alpha + c.b * (1 - alpha)),
});

// Ed Sheeran / Celestial: teal artwork, so the 8x8 average is teal.
const TEAL = { r: 18, g: 79, b: 81 };
const WARM = { r: 190, g: 110, b: 60 };

describe('rgbToHsl / hslToRgb', () => {
  it('round-trips a colour', () => {
    const { h, s, l } = rgbToHsl(TEAL.r, TEAL.g, TEAL.b);
    const back = hslToRgb(h, s, l);
    expect(back[0]).toBeCloseTo(TEAL.r, -1);
    expect(back[1]).toBeCloseTo(TEAL.g, -1);
    expect(back[2]).toBeCloseTo(TEAL.b, -1);
  });

  it('reports grey as zero saturation', () => {
    expect(rgbToHsl(128, 128, 128).s).toBe(0);
  });

  it('places teal in the cyan half of the wheel', () => {
    const { h } = rgbToHsl(TEAL.r, TEAL.g, TEAL.b);
    expect(h).toBeGreaterThan(150);
    expect(h).toBeLessThan(210);
  });
});

describe('accentFor', () => {
  it('returns null without an ambient colour, so CSS can fall back', () => {
    // ImmersiveMode sets --immersive-accent from cssRgb(accent); undefined must
    // leave the brand accent in place rather than render "rgb(undefined...)".
    expect(accentFor(null)).toBeNull();
    expect(cssRgb(null)).toBeUndefined();
  });

  it('moves a teal cover into the warm half of the wheel', () => {
    const accent = accentFor(TEAL);
    const { h } = rgbToHsl(accent.r, accent.g, accent.b);
    // 182 + 210 = 392 % 360 = 32 — amber. Warm, so the page keeps the brand's
    // temperature instead of flipping to a cold complementary hue.
    expect(h).toBeGreaterThan(15);
    expect(h).toBeLessThan(60);
  });

  it('is readable on the background it was derived from', () => {
    const accent = accentFor(TEAL);
    const r = ratio(accent, tinted(TEAL));
    expect(r, `derived accent contrast = ${r.toFixed(2)}`).toBeGreaterThanOrEqual(4.5);
  });

  it('beats the brand red that it replaces', () => {
    // The regression this exists for: #e24329 on the same background.
    const brand = { r: 0xe2, g: 0x43, b: 0x29 };
    const bg = tinted(TEAL);
    const before = ratio(brand, bg);
    const after = ratio(accentFor(TEAL), bg);
    expect(before).toBeLessThan(4.5);              // the old value failed
    expect(after).toBeGreaterThan(before);         // and the new one improves it
  });

  it('keeps a warm cover warm rather than forcing one hue', () => {
    // A warm cover must not be rotated into something cold — the accent follows
    // the artwork in both directions.
    const accent = accentFor(WARM);
    const { h } = rgbToHsl(accent.r, accent.g, accent.b);
    expect(h).toBeGreaterThan(0);
    expect(h).toBeLessThan(120);
  });
});
