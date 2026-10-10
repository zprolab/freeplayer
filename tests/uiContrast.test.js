import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

// "Nothing may be too faint to read" is a property of the token layer, so it is
// asserted here rather than eyeballed per screen. Every text token is checked
// against every surface it can legitimately land on, at WCAG AA.
const root = join(__dirname, '..', 'src');

function readTokens(file) {
  const css = readFileSync(join(root, 'ui', 'tokens', file), 'utf8');
  const vars = new Map();
  for (const m of css.matchAll(/(--[a-z0-9-]+)\s*:\s*([^;]+);/gi)) vars.set(m[1], m[2].trim());
  return vars;
}

const primitives = readTokens('primitive.css');
const semantics = readTokens('semantic.css');

// Resolve a semantic token through the primitive layer.
function resolve(name) {
  const value = semantics.get(name) ?? primitives.get(name);
  if (!value) return null;
  const ref = value.match(/^var\((--[a-z0-9-]+)\)$/i);
  if (ref) return resolve(ref[1]);
  return value;
}

function toRgb(css) {
  const hex = css.trim();
  if (/^#[0-9a-f]{3}$/i.test(hex)) {
    return [1, 2, 3].map((i) => parseInt(hex[i] + hex[i], 16));
  }
  if (/^#[0-9a-f]{6}$/i.test(hex)) {
    return [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
  }
  const rgba = hex.match(/^rgba?\(([^)]+)\)$/i);
  if (rgba) {
    const parts = rgba[1].split(',').map((p) => parseFloat(p));
    if (parts.length === 4 && parts[3] < 1) return null; // needs compositing; skip
    return parts.slice(0, 3);
  }
  return null;
}

function channel(c) {
  const v = c / 255;
  return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4;
}

function luminance(rgb) {
  const [r, g, b] = rgb.map(channel);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(fgCss, bgCss) {
  const fg = toRgb(fgCss);
  const bg = toRgb(bgCss);
  if (!fg || !bg) return null;
  const a = luminance(fg);
  const b = luminance(bg);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

const AA_NORMAL = 4.5;
const AA_LARGE = 3.0;

// Surfaces each role can appear on, by role name.
const LIGHT_SURFACES = ['--fp-surface-canvas', '--fp-surface-raised', '--fp-surface-sunken'];
const CHROME_SURFACES = ['--fp-surface-chrome', '--fp-surface-chrome-hover'];
const INSTRUMENT_SURFACES = ['--fp-surface-instrument', '--fp-surface-instrument-deep'];

describe('readability (WCAG AA) of the token layer', () => {
  it('body and muted text pass AA on every light surface', () => {
    const failures = [];
    for (const text of ['--fp-text-default', '--fp-text-muted', '--fp-text-subtle']) {
      for (const surface of LIGHT_SURFACES) {
        const r = contrast(resolve(text), resolve(surface));
        expect(r, `${text} on ${surface} could not be resolved`).not.toBeNull();
        if (r < AA_NORMAL) failures.push(`${text} on ${surface} = ${r.toFixed(2)}`);
      }
    }
    expect(failures).toEqual([]);
  });

  it('text on the sidebar chrome passes AA', () => {
    const failures = [];
    for (const text of ['--fp-text-inverse', '--fp-text-chrome-muted']) {
      for (const surface of CHROME_SURFACES) {
        const r = contrast(resolve(text), resolve(surface));
        if (r < AA_NORMAL) failures.push(`${text} on ${surface} = ${r.toFixed(2)}`);
      }
    }
    expect(failures).toEqual([]);
  });

  it('visualiser axis labels pass AA on the instrument surfaces', () => {
    const failures = [];
    for (const surface of INSTRUMENT_SURFACES) {
      for (const text of ['--fp-text-on-instrument', '--fp-text-on-instrument-muted']) {
        const r = contrast(resolve(text), resolve(surface));
        if (r < AA_NORMAL) failures.push(`${text} on ${surface} = ${r.toFixed(2)}`);
      }
    }
    expect(failures).toEqual([]);
  });

  it('status colours stay legible as text on cards', () => {
    const card = resolve('--fp-surface-raised');
    const failures = [];
    for (const role of ['--fp-info', '--fp-success', '--fp-danger']) {
      const r = contrast(resolve(role), card);
      if (r < AA_NORMAL) failures.push(`${role} = ${r.toFixed(2)}`);
    }
    expect(failures).toEqual([]);
  });

  it('keeps the brand accent above the AA large/graphics floor on cards', () => {
    // The orange is used both as a button FILL (large/graphics, 3:1) and as
    // text/icons. As a fill it is fine; as text it is documented as the one
    // deliberate exception, so assert the floor it does meet rather than
    // letting it drift further.
    const r = contrast(resolve('--fp-accent'), resolve('--fp-surface-raised'));
    expect(r).toBeGreaterThanOrEqual(AA_LARGE);
  });

  it('records the contrast improvements this pass made', () => {
    // Guards against a silent revert to the washed-out values.
    expect(resolve('--fp-text-subtle')).toBe('#6b6b73');
    expect(resolve('--fp-text-chrome-muted')).toBe('#a8a8b0');
    expect(resolve('--fp-text-on-instrument-muted')).toBe('#b4b4bc');
  });
});
