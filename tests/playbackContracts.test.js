// Interface contracts for the two swappable playback collaborators.
//
// WHY THIS EXISTS: PlaybackEngine and AudioEngine are the two places a second
// implementation could plausibly land (an FFmpeg decoder feeding Web Audio
// instead of a media element, a different analysis graph). Before replacing
// either, the question is "what exactly must the replacement provide?" — and the
// honest answer is not a list someone typed out, it is the set of members the
// consumers actually touch.
//
// So the surface is DERIVED from the consuming source, not hand-maintained:
// every `engine.x` / `audioEngine.x` in production code must exist on the real
// implementation, and the required event names must be emitted. Add a call site
// that uses something new and this fails until the contract is updated — which
// is the point, because an interface nobody checks drifts.
//
// No production code changes are required for this file to be useful: it is a
// description of what already exists, with the difference that it can fail.

import { describe, it, expect } from 'vitest';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { PlaybackEngine, mediaSrcFor } from '@/features/playback/engine.js';
import { AudioEngine } from '@/features/playback/audio.js';

const root = join(__dirname, '..', 'src');

function walk(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) return walk(full);
    return /\.(js|jsx)$/.test(full) ? [full] : [];
  });
}

/** Members referenced as `<receiver>.<name>` across production sources. */
function membersUsedOn(receiver, { exclude = [] } = {}) {
  const used = new Set();
  for (const file of walk(root)) {
    if (exclude.some((e) => file.endsWith(e))) continue;
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(new RegExp(`\\b${receiver}\\.([A-Za-z_][A-Za-z0-9_]*)`, 'g'))) {
      // `import ... from '...engine.js'` produces the member name `js`; a file
      // extension is not an interface member.
      if (/^(js|jsx|json|css)$/.test(m[1])) continue;
      used.add(m[1]);
    }
  }
  return used;
}

describe('PlaybackEngine contract', () => {
  // Derived from EVERY production file that touches `engine`. Computed inside the
  // assertion, not at module load: a snapshot taken at import time would not
  // reflect the file as it is when the test runs, which is the whole point.
  // (engine.js defines the members, so its own `this.x` is not a consumer use.)
  const exclude = ['playback/engine.js'];

  it('is the only place the engine is constructed from', () => {
    // A second `new PlaybackEngine()` elsewhere would mean two transports over
    // one audio element — the exact class of bug the singleton prevents.
    const constructions = walk(root)
      .filter((f) => !f.endsWith('features/playback/engine.js'))
      .filter((f) => /new PlaybackEngine\(/.test(readFileSync(f, 'utf8')))
      .map((f) => f.replace(`${root}/`, ''));
    expect(constructions).toEqual([]);
  });

  it('exposes every member the adapter actually uses', () => {
    const used = membersUsedOn('engine', { exclude });
    expect(used.size, 'no consumer found — the scan is broken').toBeGreaterThan(0);
    const real = new PlaybackEngine({ audio: null, bridge: null });
    const missing = [...used].filter((name) => {
      // Methods live on the prototype; state is assigned in the constructor.
      return !(name in real) && typeof real[name] === 'undefined';
    });
    expect(missing, `consumers use ${missing.join(', ')} but the engine lacks them`).toEqual([]);
  });

  it('treats audio and bridge as assignable — the adapter injects them', () => {
    // `engine.audio = audioRef.current` and `engine.bridge = window.freeplayer`
    // run on every mount, so a replacement must accept both as assignable
    // properties rather than constructor-only options.
    const real = new PlaybackEngine({ audio: null, bridge: null });
    const el = { play: () => {}, pause: () => {} };
    real.audio = el;
    real.bridge = { logDiagnostic: () => {} };
    expect(real.audio).toBe(el);
    expect(real.bridge).toBeTruthy();
  });

  it('emits exactly the events the adapter subscribes to', () => {
    const adapter = readFileSync(join(root, 'features/playback/usePlayback.js'), 'utf8');
    // Only the switch INSIDE engine.subscribe(...) — the same file also switches
    // on native bridge actions (playpause/next/previous), which are push
    // messages from the tray and media keys, not engine events.
    const subscribeBlock = adapter.slice(adapter.indexOf('engine.subscribe('));
    const body = subscribeBlock.slice(0, subscribeBlock.indexOf('return unsubscribe'));
    const handled = new Set([...body.matchAll(/case '([a-z]+)':/g)].map((m) => m[1]));
    expect(handled.size, 'the adapter must switch on at least one event').toBeGreaterThan(0);

    const engineSrc = readFileSync(join(root, 'features/playback/engine.js'), 'utf8');
    const emitted = new Set([...engineSrc.matchAll(/_emit\('([a-z]+)'/g)].map((m) => m[1]));
    const unhandled = [...handled].filter((e) => !emitted.has(e));
    expect(unhandled, `adapter handles ${unhandled.join(', ')} which the engine never emits`).toEqual([]);
  });

  it('reports transport state the adapter reads directly', () => {
    const real = new PlaybackEngine({ audio: null, bridge: null });
    // Read as `engine.paused` and `engine.currentTime` in the adapter.
    expect(typeof real.paused).toBe('boolean');
    expect(typeof real.currentTime).toBe('number');
  });
});

describe('AudioEngine (media graph) contract', () => {
  // Consumers: the engine drives it, the visualiser reads FFT data from it, the
  // quality preference sets its FFT size.
  const used = membersUsedOn('audioEngine', { exclude: ['features/playback/audio.js'] });

  it('exposes every member its consumers use', () => {
    const real = new AudioEngine();
    const missing = [...used].filter((name) => !(name in real));
    expect(missing, `consumers use ${missing.join(', ')} but AudioEngine lacks them`).toEqual([]);
  });

  it('keeps the graph construction inside connect(), not the constructor', () => {
    // WKWebView refuses to start an AudioContext without a user gesture, so a
    // replacement that builds the graph eagerly would throw on load.
    const real = new AudioEngine();
    expect(real.ctx == null, 'constructing AudioEngine must not create an AudioContext').toBe(true);
    expect(typeof real.connect).toBe('function');
  });

  it('subscription returns an unsubscribe function', () => {
    // useVisualizerQuality relies on this to detach without leaking a listener.
    const real = new AudioEngine();
    const off = real.subscribeFftSize(() => {});
    expect(typeof off).toBe('function');
    off();
  });
});

describe('mediaSrcFor (the local-file source strategy)', () => {
  it('percent-encodes the WHOLE path, including # and ?', () => {
    // encodeURI leaves '#' and '?' unescaped and WebKit reads them as
    // fragment/query, truncating the path — hence encodeURIComponent here.
    const src = mediaSrcFor('/Music/a#b?c.flac');
    expect(src.startsWith('media://')).toBe(true);
    expect(src).not.toContain('#');
    expect(src).not.toContain('?');
  });

  it('round-trips through decodeURIComponent', () => {
    const path = '/Users/x/Music/Ed Sheeran/Celestial.flac';
    expect(decodeURIComponent(mediaSrcFor(path).slice('media://'.length))).toBe(path);
  });
});
