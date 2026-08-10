import lrclibManifest from './lrclib/manifest.json';
import * as lrclibMain from './lrclib/main.js';
import itunesManifest from './itunes/manifest.json';
import * as itunesMain from './itunes/main.js';
export const BUILTIN_PLUGINS = [
  { id: 'lrclib-lyrics', manifestRaw: lrclibManifest, builtin: true, module: lrclibMain },
  { id: 'itunes-cover', manifestRaw: itunesManifest, builtin: true, module: itunesMain },
];
