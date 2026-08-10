import { collectModuleGraph, rewriteModule, resolveRelPath } from './collect';
import { wrapApi } from './api';
import { hookTimeout } from './hooks';

export function blobUrlForModule(module) {
  return URL.createObjectURL(new Blob([module.source], { type: 'text/javascript' }));
}

export function createLoader(deps) {
  const { readFile, importUrl, createApi, onDenied, hookTimeoutMs = 15000 } = deps;

  async function activate(pluginId, entry) {
    const { manifest, builtin, module: builtinModule, granted } = entry;
    const blobUrls = new Set();
    let mainUrl;
    let mainModule = builtinModule;
    if (!builtinModule) {
      if (builtin) {
        mainUrl = manifest.main;
      } else {
        const graph = await collectModuleGraph(manifest.main, (rel) => readFile(pluginId, rel));
        if (graph.error) throw new Error(graph.error);
        // collectModuleGraph 输出后序（依赖在前），重写任一模块时其依赖的最终 URL 已在 map 中
        const urls = new Map();
        for (const mod of graph.modules) {
          mod.source = rewriteModule(mod.source, (spec) => {
            const rel = resolveRelPath(mod.path, spec);
            const url = rel ? urls.get(rel) : null;
            return url ? { url } : null;
          });
          const url = blobUrlForModule(mod);
          blobUrls.add(url);
          urls.set(mod.path, url);
        }
        mainUrl = urls.get(manifest.main);
      }
      mainModule = await importUrl(mainUrl);
    }
    if (!mainModule || typeof mainModule.activate !== 'function') {
      throw new Error('activate failed: plugin does not export activate(api)');
    }
    const api = wrapApi(pluginId, granted || manifest.permissions, createApi(pluginId), (key) => onDenied(pluginId, key));
    const hooks = await hookTimeout(() => mainModule.activate(api), hookTimeoutMs);
    if (!hooks || typeof hooks !== 'object') {
      throw new Error('activate failed: activate(api) must return a hooks object');
    }
    if (manifest.provides.lyrics && typeof hooks.fetchLyrics !== 'function') {
      throw new Error('missing hook: fetchLyrics');
    }
    if (manifest.provides.cover && typeof hooks.fetchCover !== 'function') {
      throw new Error('missing hook: fetchCover');
    }
    return {
      hooks,
      deactivate: () => {
        for (const u of blobUrls) URL.revokeObjectURL(u);
        blobUrls.clear();
        mainModule.deactivate?.();
      },
      api,
    };
  }

  return { activate };
}
