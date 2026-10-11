import lrclibManifest from '@/plugins/builtin/lrclib/manifest.json';
import * as lrclibMain from '@/plugins/builtin/lrclib/main.js';
import itunesManifest from '@/plugins/builtin/itunes/manifest.json';
import * as itunesMain from '@/plugins/builtin/itunes/main.js';
import musicbrainzManifest from '@/plugins/builtin/musicbrainz/manifest.json';
import * as musicbrainzMain from '@/plugins/builtin/musicbrainz/main.js';
export const BUILTIN_PLUGINS = [
  { id: 'lrclib-lyrics', manifestRaw: lrclibManifest, builtin: true, module: lrclibMain },
  { id: 'itunes-cover', manifestRaw: itunesManifest, builtin: true, module: itunesMain },
  { id: 'musicbrainz-meta', manifestRaw: musicbrainzManifest, builtin: true, module: musicbrainzMain },
];
