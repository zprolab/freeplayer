// The immersive accent is derived from the cover's average colour so the
// highlight, its indicator bar and the progress fill all belong to the artwork
// instead of fighting it. The look cannot be asserted here; the rules can.
//
// Kept deliberately small. An earlier version of this suite measured WCAG
// contrast and drove the implementation into a max-contrast search that converged
// on near-white — enforcing a rule nobody had asked for, and destroying the
// colour in the process.
import { describe, it, expect } from 'vitest';
import { rgbToHsl, hslToRgb, accentFor, cssRgb, relativeLuminance } from '@/features/playback/ambientColor.js';

// Ed Sheeran / Celestial: teal artwork, so the 8x8 average is teal.
const TEAL = { r: 18, g: 79, b: 81 };
const WARM = { r: 190, g: 110, b: 60 };
const LIGHT = { r: 236, g: 232, b: 226 };

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
    expect(accentFor(null)).toBeNull();
    expect(cssRgb(null)).toBeUndefined();
  });

  it('moves a cool cover into the warm half of the wheel', () => {
    // Cool cover gets a warm accent, so it never lands on the field's complement.
    const a = accentFor(TEAL);
    const { h } = rgbToHsl(a.r, a.g, a.b);
    expect(h).toBeGreaterThan(15);
    expect(h).toBeLessThan(60);
  });

  it('keeps a warm cover warm rather than forcing one hue', () => {
    // A warm cover would be sent to blue by a fixed rotation, contradicting the
    // artwork it came from.
    const a = accentFor(WARM);
    const { h } = rgbToHsl(a.r, a.g, a.b);
    expect(h).toBeGreaterThan(0);
    expect(h).toBeLessThan(90);
  });

  it('stays a colour, not a grey or a near-white', () => {
    // The regression this guards: the max-contrast search returned
    // rgb(252,236,217) for a teal cover — white in all but name.
    for (const cover of [TEAL, LIGHT, WARM]) {
      const a = accentFor(cover);
      const { s } = rgbToHsl(a.r, a.g, a.b);
      expect(s, `accent for ${JSON.stringify(cover)} lost its hue`).toBeGreaterThan(0.3);
    }
  });

  it('inverts lightness against the field', () => {
    const onDark = accentFor(TEAL);
    const onLight = accentFor(LIGHT);
    expect(relativeLuminance(TEAL)).toBeLessThan(0.5);
    expect(relativeLuminance(LIGHT)).toBeGreaterThan(0.5);
    // Dark field → lighter accent; light field → darker accent.
    expect(relativeLuminance(onDark)).toBeGreaterThan(relativeLuminance(onLight));
  });
});
