import { describe, it, expect, vi } from 'vitest';
import { BUILTIN_PLUGINS } from '../../src/plugins/builtin';
import { validateManifest } from '../../src/plugins/manifest';
import { createLoader } from '../../src/plugins/loader';

describe('BUILTIN_PLUGINS', () => {
  it('entries carry id/manifestRaw/builtin/module with a valid manifest', () => {
    expect(BUILTIN_PLUGINS.map((p) => p.id)).toEqual(['lrclib-lyrics', 'itunes-cover']);
    for (const p of BUILTIN_PLUGINS) {
      expect(p.builtin).toBe(true);
      expect(p.manifestRaw.id).toBe(p.id);
      expect(validateManifest(p.manifestRaw).ok).toBe(true);
      expect(typeof p.module.activate).toBe('function');
    }
  });
  it('the loader activates each builtin via its module, without importUrl', async () => {
    const loader = createLoader({
      readFile: vi.fn(async () => null),
      importUrl: vi.fn(async () => { throw new Error('importUrl must not be used for builtins'); }),
      createApi: vi.fn((id) => ({
        http: {
          getJson: vi.fn(async () => ({ ok: true, status: 200, body: { syncedLyrics: '[00:01.00]hi' } })),
          getBase64: vi.fn(async () => ({ ok: true, status: 200, base64: 'b64' })),
        },
        pluginSettings: { get: vi.fn(async () => null) },
      })),
      onDenied: vi.fn(),
    });
    for (const p of BUILTIN_PLUGINS) {
      const entry = { manifest: validateManifest(p.manifestRaw).manifest, builtin: true, module: p.module };
      const res = await loader.activate(p.id, entry);
      const hook = res.hooks.fetchLyrics || res.hooks.fetchCover;
      expect(typeof hook).toBe('function');
      res.deactivate();
    }
  });
});
