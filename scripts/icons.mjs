#!/usr/bin/env node
// FreePlayer — icon pipeline.
// Single source of truth: ../assets/logo.svg (the glyph, no background).
// Everything here is a BUILD-TIME composition — this script is the only place
// the icon background is defined (tile fill, corner radius):
//   - composes tile + glyph → renders shell/FreePlayer-1024.png (1024px master)
//   - renders the macOS iconset sizes → iconutil → shell/FreePlayer.icns
//   - renders the iOS AppIcon (square — iOS applies its own mask) into
//     shell/Assets.xcassets/AppIcon.appiconset/
// Requires: node + @resvg/resvg-js (devDependency); iconutil ships with macOS.
// CI-safe on macOS runners; the web build never invokes this.
import { readFileSync, writeFileSync, mkdtempSync, mkdirSync, rmSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import os from 'node:os';
import { Resvg } from '@resvg/resvg-js';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SRC = join(ROOT, 'assets', 'logo.svg');
const OUT_PNG = join(ROOT, 'shell', 'FreePlayer-1024.png');
const OUT_ICNS = join(ROOT, 'shell', 'FreePlayer.icns');
const IOS_APPICON_DIR = join(ROOT, 'shell', 'Assets.xcassets', 'AppIcon.appiconset');
const IOS_APPICON_PNG = join(IOS_APPICON_DIR, 'AppIcon-1024.png');
const IOS_APPICON_JSON = join(IOS_APPICON_DIR, 'Contents.json');

// ── icon tile recipe (the ONLY place background styling lives) ─────────────
const TILE_FILL = '#1f1f23';   // matches the authoritative Pixelmator export
// macOS applies its own squircle mask on the Dock; a near-square tile leaves
// its corners clipped → a visible border ring around the icon. Give the tile
// the standard macOS corner radius (~22% of size) so the mask hugs the
// content and the icon fills the Dock slot edge-to-edge.
const TILE_RADIUS = 280;       // in 1280 artspace (~21.9%)
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
  return `<defs>${grad ? grad[0] : ''}</defs>${rest}`;
}

function composedSvg(radius) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="1280" viewBox="0 0 1280 1280">
  <rect x="0" y="0" width="1280" height="1280" rx="${radius}" fill="${TILE_FILL}"/>
  ${glyphSvg()}
</svg>`;
}

function render(svg, px) {
  const resvg = new Resvg(svg, { fitTo: { mode: 'width', value: px } });
  return resvg.render().asPng();
}

const svg = composedSvg(TILE_RADIUS);

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

// iOS AppIcon — square tile (iOS renders its own rounded mask + shadows), so
// the exported bitmap must be a full-bleed square with no corner rounding.
mkdirSync(IOS_APPICON_DIR, { recursive: true });
writeFileSync(IOS_APPICON_PNG, render(composedSvg(0), 1024));
writeFileSync(IOS_APPICON_JSON, JSON.stringify({
  images: [{ filename: 'AppIcon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }],
  info: { author: 'xcode', version: 1 },
}, null, 2) + '\n');
console.log(`==> ${IOS_APPICON_PNG}`);