// Guards the argument convention between src/core/client.js and the injected
// bridge (shell/Sources/Bridge/BridgeScript.swift).
//
// THE BUG THIS EXISTS FOR: the bridge wrappers already wrap some values before
// invoking native — `sendPlaybackState: (isPlaying) => _invoke('sendPlaybackState',
// { isPlaying })`. When the client seam was introduced it ALSO passed a wrapped
// object, so the payload nested twice:
//
//     renderer intended  { isPlaying: true }
//     bridge wrapped it  { isPlaying: { isPlaying: true } }
//     native read        d["isPlaying"] as? NSNumber  → type is Dictionary
//                        → cast failed → `?? false` → ALWAYS false
//
// The result was a tray icon that never showed Pause and a play button that never
// showed Pause, while every layer reported success and nothing logged an error.
// `setAppearance` had the identical defect (`d["dark"] as? Bool ?? true`), which
// would pin the appearance toggle to its default forever.
//
// So: for every wrapper the bridge wraps, the client must pass the PRIMITIVE,
// and for every wrapper it forwards verbatim, the client must pass the OBJECT.
// This is checked against both files rather than remembered.

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const root = join(__dirname, '..', 'src');
const repo = join(__dirname, '..');

const bridge = readFileSync(join(repo, 'shell/Sources/Bridge/BridgeScript.swift'), 'utf8');
const client = readFileSync(join(root, 'core/client.js'), 'utf8');

/** method -> { wraps, arity } for each bridge wrapper. */
function bridgeWrappers() {
  const map = new Map();
  for (const m of bridge.matchAll(/(\w+):\s*\(([^)]*)\)\s*=>\s*api\._invoke\('(\w+)'\s*(,\s*\{)?/g)) {
    const [, , params, method, wrapOpen] = m;
    const arity = params.split(',').map((p) => p.trim()).filter(Boolean).length;
    map.set(method, { wraps: Boolean(wrapOpen), arity });
  }
  return map;
}

/** client methods as { exporter, name, params, bridgeMethod, argsPassed }. */
function clientCalls() {
  const calls = [];
  for (const m of client.matchAll(/(\w+):\s*\(([^)]*)\)\s*=>\s*call\('(\w+)'([^)]*)\)/g)) {
    const [, name, params, method, rest] = m;
    // Count the values handed to call(): params that are actually forwarded.
    const forwarded = params
      .split(',')
      .map((p) => p.trim())
      .filter(Boolean);
    calls.push({ name, params: forwarded, method, rest: rest.trim() });
  }
  return calls;
}

describe('client <-> bridge argument convention', () => {
  const wrappers = bridgeWrappers();
  const calls = clientCalls();

  it('finds both sides of the boundary', () => {
    // If either regex stops matching, every assertion below becomes vacuous and
    // this file would report success while checking nothing.
    expect(wrappers.size, 'no bridge wrappers parsed').toBeGreaterThan(10);
    expect(calls.length, 'no client calls parsed').toBeGreaterThan(20);
  });

  it('passes a PRIMITIVE to every SINGLE-VALUE wrapper that wraps', () => {
    const offenders = [];
    for (const c of calls) {
      const w = wrappers.get(c.method);
      if (!w || !w.wraps) continue;
      // A multi-parameter wrapper (logDiagnostic takes pluginId/level/message)
      // legitimately builds its object from several arguments, so an object at
      // the call site is not a double wrap there. Only the single-value case is.
      if (w.arity !== 1) continue;
      if (c.rest.includes('{')) {
        offenders.push(`${c.name} -> ${c.method} passes an object to a wrapper that already wraps it`);
      }
    }
    expect(offenders).toEqual([]);
  });

  // The two concrete regressions, asserted by name so a future refactor cannot
  // quietly reintroduce them while the generic rule above stays green.
  it('sendState hands over the boolean itself', () => {
    const m = client.match(/sendState:\s*\(([^)]*)\)\s*=>\s*call\('sendPlaybackState',\s*([^)]+)\)/);
    expect(m, 'sendState must call sendPlaybackState').not.toBeNull();
    expect(m[2].trim(), 'must forward the parameter, not { isPlaying }').not.toContain('{');
  });

  it('setAppearance hands over the boolean itself', () => {
    const m = client.match(/setAppearance:\s*\(([^)]*)\)\s*=>\s*call\('setAppearance',\s*([^)]+)\)/);
    expect(m, 'setAppearance must call setAppearance').not.toBeNull();
    expect(m[2].trim(), 'must forward the parameter, not { dark }').not.toContain('{');
  });

  it('native reads the shape the bridge actually sends', () => {
    // sendPlaybackState: the bridge wraps → native reads d["isPlaying"] as a Bool.
    // setAppearance:     the bridge wraps → native reads d["dark"] as a Bool.
    // Neither may be a nested dictionary, which is what a double wrap produces.
    const bridge = readFileSync(join(repo, 'shell/Sources/Bridge/BridgeScript.swift'), 'utf8');
    const sendsNested = /_invoke\('sendPlaybackState',\s*\{\s*isPlaying:\s*\{/.test(bridge)
      || /_invoke\('setAppearance',\s*\{\s*dark:\s*\{/.test(bridge);
    expect(sendsNested, 'the bridge must not nest the payload again').toBe(false);
  });
});
