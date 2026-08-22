#!/usr/bin/env node
// FreePlayer — icon pipeline.
// Single source of truth: ../assets/logo.svg (the glyph, no background).
// Everything here is a BUILD-TIME composition — this script is the only place
// the icon background is defined (tile fill, corner radius):
//   - composes tile + glyph → renders shell/FreePlayer-1024.png (1024px master)
//   - renders the macOS iconset sizes → iconutil → shell/FreePlayer.icns
// Requires: node + @resvg/resvg-js (devDependency); iconutil ships with macOS.
// CI-safe on macOS runners; the web build never invokes this.
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import { Resvg } from '@resvg/resvg-js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const SRC = join(ROOT, 'assets', 'logo.svg');
const OUT_PNG = join(ROOT, 'shell', 'FreePlayer-1024.png');
const OUT_ICNS = join(ROOT, 'shell', 'FreePlayer.icns');

// ── icon tile recipe (the ONLY place background styling lives) ─────────────
const TILE_FILL = '#1f1f23';   // matches the authoritative Pixelmator export
const TILE_RADIUS = 4;         // in 1280 artspace; matches the export's subtle corner
const GLYPH_COLOR = '#ffffff'; // how currentColor in the source resolves for the icon
// ────────────────────────────────────────────────────────────────────────────

// macOS iconset: name → pixel size
const ICONSET = [
  ['icon_16x16.png', 16], ['icon_16x16@2x.png', 32],
  ['icon_32x32.png', 32], ['icon_32x32@2x.png', 64],
  ['icon_128x128.png', 128], ['icon_128x128@2x.png', 256],
  ['icon_256x256.png', 256], ['icon_256x256@2x.png', 512],
  ['icon_512x512.png', 512], ['icon_512x512@2x.png', 1024],
];

function glyphSvg() {
  const src = readFileSync(SRC, 'utf8');
  const m = src.match(/<svg[^>]*>([\s\S]*)<\/svg>/);
  if (!m) throw new Error(`cannot parse glyph source: ${SRC}`);
  const inner = m[1];
  // hoist the gradient into <defs> (spec-compliant; resvg requires it)
  const grad = inner.match(/<linearGradient[\s\S]*?<\/linearGradient>/);
  const rest = grad ? inner.replace(grad[0], '') : inner;
  return `<defs>${grad ? grad[0] : ''}</defs>${rest}`.replaceAll('currentColor', GLYPH_COLOR);
}

function composedSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="1280" viewBox="0 0 1280 1280">
  <rect x="0" y="0" width="1280" height="1280" rx="${TILE_RADIUS}" fill="${TILE_FILL}"/>
  ${glyphSvg()}
</svg>`;
}

function render(svg, px) {
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: px } });
  return resvg.render().asPng();
}

const svg = composedSvg();

// 1024px master
writeFileSync(OUT_PNG, render(svg, 1024));
console.log(`==> ${OUT_PNG}`);

// iconset → icns
const tmp = mkdtempSync(join(os.tmpdir(), 'fp-icon-'));
const iconset = join(tmp, 'icon.iconset');
mkdirSync(iconset);
try {
  for (const [name, px] of ICONSET) writeFileSync(join(iconset, name), render(svg, px));
  execFileSync('iconutil', ['-c', 'icns', iconset, '-o', OUT_ICNS]);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
console.log(`==> ${OUT_ICNS}`);