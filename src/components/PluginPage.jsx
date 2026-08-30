import { useState, useEffect, useCallback } from 'react';
import ToggleSwitch from './ToggleSwitch';
import { sanitizeSvgIcon } from '../plugins/svgIcon';
import { backfillMissing, isBackfillRunning, needsMetadataFill } from '../services/backfill';


const PERM_DESC = {
  http: 'Make network requests (GET) — HTTPS only; localhost is allowed, LAN/loopback addresses are blocked',
  'player:read': 'Read playback state and current track',
  'player:write': 'Control playback, volume, queue',
  'audio:read': 'Access the current audio file (media:// URL)',
  'metadata:read': 'Read track metadata, lyrics, artwork',
  'metadata:write': 'Save lyrics/artwork, edit track info',
  'metadata:admin': 'Delete metadata and tracks',
  'settings:read': 'Read global settings',
  'settings:write': 'Write global settings',
  'settings:admin': 'Reset the database (not exposed in v1)',
};

// Icon string is only ever injected as HTML through the SVG sanitizer —
// never raw. Error/incompatible plugins keep their raw (unvalidated)
// manifest, so this second gate matters even though the registry sanitizes.
function renderableIcon(icon) {
  if (typeof icon !== 'string' || !icon) return { svg: null, img: null };
  if (icon.includes('<')) return { svg: sanitizeSvgIcon(icon), img: null };
  return { svg: null, img: null };
}

function permDesc(perm) {
  return PERM_DESC[perm] || 'Access requested by this plugin';
}

export default function PluginPage({ registry, meta, tracks }) {
  const [plugins, setPlugins] = useState([]);
  const [refreshing, setRefreshing] = useState(false);
  const [pendingPlugin, setPendingPlugin] = useState(null); // 权限弹窗对象 { id, manifest }
  const [refetchConfirm, setRefetchConfirm] = useState(null); // { p, kind } 强制重新获取确认
  const [pendingGrants, setPendingGrants] = useState([]);
  const [openDetail, setOpenDetail] = useState(null); // 详情面板插件 id
  const [detailTab, setDetailTab] = useState('settings');
  const [settingsValues, setSettingsValues] = useState({});
  const [diagnosticsPath, setDiagnosticsPath] = useState('');
  const [managedContainerPath, setManagedContainerPath] = useState('');
  const [autoFetch, setAutoFetch] = useState({}); // { [pluginId]: boolean }
  const [backfillProgress, setBackfillProgress] = useState(null); // { pluginId, done, total, ok, fail, noMatch }

  // Auto-fetch switches (plugin.<id>.autoFetch, default off) for provider
  // plugins — each backend controls its own missing-metadata auto-fetch.
  useEffect(() => {
    if (!openDetail) return;
    let cancelled = false;
    (async () => {
      const v = await window.freeplayer.getSetting(`plugin.${openDetail}.autoFetch`).catch(() => null);
      if (cancelled) return;
      const s = String(v ?? '').toLowerCase();
      setAutoFetch((a) => ({ ...a, [openDetail]: s === '1' || s === '1.0' || s === 'true' || s === 'yes' || s === 'on' }));
    })();
    return () => { cancelled = true; };
  }, [openDetail]);

  useEffect(() => {
    if (openDetail !== 'managed-library') return;
    window.freeplayer?.getSetting?.('library_dir').then((dir) => {
      if (dir) setManagedContainerPath(`${dir}/FreePlayer.fpmlib`);
    }).catch(() => {});
  }, [openDetail]);

  const handleAutoFetchChange = (pluginId, val) => {
    setAutoFetch((a) => ({ ...a, [pluginId]: val }));
    window.freeplayer.setSetting({ key: `plugin.${pluginId}.autoFetch`, value: val ? '1' : '0' }).catch(() => {});
  };

  const handleBackfill = async (p, kind, force = false) => {
    if (isBackfillRunning() || !meta) return;
    // Progress is keyed per plugin+kind so a plugin with several
    // capabilities (e.g. musicbrainz: cover + metadata) keeps each
    // row's progress isolated from the others.
    const key = `${p.id}:${kind}`;
    setBackfillProgress({ key, done: 0, total: tracks?.length || 0, ok: 0, fail: 0, noMatch: 0 });
    await backfillMissing({
      tracks,
      kind,
      force,
      fetchForTrack: (t) => (
        kind === 'lyrics' ? meta.fetchLyrics(t)
          : kind === 'cover' ? meta.fetchCover(t)
          : meta.fetchMetadata(t)
      ),
      missingCheck: async (t) => {
        if (kind === 'lyrics') {
          const lrc = await window.freeplayer.getLrc(t.id).catch(() => null);
          return !lrc || !lrc.content;
        }
        if (kind === 'cover') {
          return !t.cover_path
            || !(await window.freeplayer.getCover(t.cover_path).catch(() => null));
        }
        return needsMetadataFill(t);
      },
      onProgress: (prog) => setBackfillProgress({ key, ...prog }),
    });
    setBackfillProgress(null);
  };

  // 声明式设置：按 manifest.settings 声明从 plugin.<id>.<key> 读取初始值
  // （与 api.pluginSettings 命名空间一致），JSON.parse 兜底还原类型。
  useEffect(() => {
    if (!openDetail) return;
    const p = plugins.find((x) => x.id === openDetail);
    if (!p || !Array.isArray(p.manifest.settings)) return;
    let cancelled = false;
    (async () => {
      const entries = await Promise.all(p.manifest.settings.map(async (s) => {
        let value = s.default;
        try {
          const stored = await window.freeplayer.getSetting(`plugin.${p.id}.${s.key}`);
          if (stored != null) {
            try { value = JSON.parse(stored); } catch { value = stored; }
          }
        } catch { /* 读取失败保持 default */ }
        return [s.key, value];
      }));
      if (cancelled) return;
      setSettingsValues((v) => ({ ...v, [p.id]: Object.fromEntries(entries) }));
    })();
    return () => { cancelled = true; };
  }, [openDetail, plugins]);

  useEffect(() => {
    if (openDetail !== 'diagnostics-log') return;
    window.freeplayer?.getDiagnosticsPath?.().then(setDiagnosticsPath).catch(() => {});
  }, [openDetail]);

  const isNew = (p) => !p.perms.enabled && p.perms.granted.length === 0;

  function handleSettingChange(p, s, value) {
    setSettingsValues((v) => ({ ...v, [p.id]: { ...(v[p.id] || {}), [s.key]: value } }));
    // JSON 序列化保持类型：number/boolean 存字面量（"1200"/"true"），读取时 JSON.parse 还原
    window.freeplayer.setSetting({ key: `plugin.${p.id}.${s.key}`, value: JSON.stringify(value) }).catch(() => {});
  }

  const refresh = useCallback(async () => {
    setRefreshing(true);
    try {
      await registry.refresh();
      setPlugins([...registry.getPlugins()].sort((a, b) => {
        const order = { NEW: 0, incompatible: 1, error: 2, enabled: 3, active: 3, disabled: 4 };
        // NEW 置顶：perms.enabled=false 且未授权过
        return Number(isNew(a)) - Number(isNew(b)) || order[a.status] - order[b.status] || a.id.localeCompare(b.id);
      }));
    } finally {
      setRefreshing(false);
    }
  }, [registry]);

  useEffect(() => { refresh(); }, [refresh]);

  // 后端下拉初始化：读取已存 meta.lyricsBackend / meta.coverBackend /
  // meta.metadataBackend，与 metadataRegistry.backendFor 的取值保持一致
  // （未加载/无存值时回落默认）。
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [lyrics, cover, metadata] = await Promise.all([
          window.freeplayer.getSetting('meta.lyricsBackend'),
          window.freeplayer.getSetting('meta.coverBackend'),
          window.freeplayer.getSetting('meta.metadataBackend'),
        ]);
        if (cancelled) return;
        setSettingsValues((s) => ({
          ...s,
          lyricsBackend: lyrics || s.lyricsBackend,
          coverBackend: cover || s.coverBackend,
          metadataBackend: metadata || s.metadataBackend,
        }));
      } catch {
        // 读取失败则保持默认值
      }
    })();
    return () => { cancelled = true; };
  }, []);

  async function handleToggle(p, enabled) {
    try {
      if (enabled) {
        if (isNew(p)) {
          // Default: read-level grants only. http is deliberately NOT
          // pre-checked — an http grant can reach localhost/LAN services, so
          // the user should opt in explicitly after reviewing what the plugin
          // is for. Providers additionally need metadata:write — the host
          // persists their hook results on their behalf, so the write grant
          // is required for them to function.
          const defaults = (p.manifest.permissions || []).filter((x) => x.endsWith(':read'));
          if ((p.manifest.provides?.lyrics || p.manifest.provides?.cover)
              && (p.manifest.permissions || []).includes('metadata:write')
              && !defaults.includes('metadata:write')) {
            defaults.push('metadata:write');
          }
          setPendingPlugin(p);
          setPendingGrants(defaults);
          return;
        }
        // 重新启用：保留既有 granted（disable 不清空），避免静默降权
        await registry.enable(p.id, p.perms.granted);
      } else {
        await registry.disable(p.id);
      }
      if (p.id === 'diagnostics-log' && window.freeplayer?.setDiagnosticsEnabled) {
        await window.freeplayer.setDiagnosticsEnabled(enabled);
      }
      if (p.id === 'managed-library') {
        await window.freeplayer.setSetting({ key: 'managed_library_enabled', value: enabled ? '1' : '0' });
      }
      await refresh();
    } catch (err) {
      console.warn(`[plugins] toggle ${p.id}:`, err.message || err);
    }
  }

  async function confirmEnable() {
    try {
      await registry.enable(pendingPlugin.id, pendingGrants);
      if (pendingPlugin.id === 'diagnostics-log' && window.freeplayer?.setDiagnosticsEnabled) {
        await window.freeplayer.setDiagnosticsEnabled(true);
      }
      if (pendingPlugin.id === 'managed-library') {
        await window.freeplayer.setSetting({ key: 'managed_library_enabled', value: '1' });
      }
      setOpenDetail(pendingPlugin.id); setDetailTab('settings');
      setPendingPlugin(null);
      await refresh();
    } catch (err) {
      console.warn(`[plugins] enable ${pendingPlugin?.id}:`, err.message || err);
    }
  }

  async function updateGrants(p, perm, on) {
    try {
      const [domain, level] = perm.split(':');
      let next = on ? [...p.perms.granted, perm] : p.perms.granted.filter((x) => x !== perm);
      if (on && level === 'write' && !next.includes(`${domain}:read`)) next = [...next, `${domain}:read`];
      if (!on && level === 'read') next = next.filter((x) => x !== `${domain}:write`);
      await registry.enable(p.id, next);
      await refresh();
    } catch (err) {
      console.warn(`[plugins] grants ${p.id}:`, err.message || err);
    }
  }

  const noticePlugins = plugins.filter(isNew);
  return (
    <div className="plugins-page">
      <div className="page-header">
        <div className="page-title">Plugins</div>
        <span className="track-count-badge">{plugins.length} plugins</span>
      </div>
      <div className="plugins-content">
        {noticePlugins.length > 0 && (
          <div className="plugins-notice">
            <span>{noticePlugins.length} new plugin{noticePlugins.length > 1 ? 's' : ''} found</span>
            <button className="btn btn-secondary" onClick={() => setOpenDetail(noticePlugins[0].id)}>View</button>
          </div>
        )}
        {plugins.map((p) => (
          <div key={p.id} className={`plugin-card${isNew(p) ? ' plugin-card--new' : ''}`} onClick={() => { setOpenDetail(p.id); setDetailTab('settings'); }}>
            <div className="plugin-card-avatar">
              {(() => {
                const { svg, img } = renderableIcon(p.manifest.icon);
                if (svg) return <span className="plugin-card-icon" dangerouslySetInnerHTML={{ __html: svg }} />;
                if (img) return <img className="plugin-card-icon" src={img} alt="" />;
                return (p.manifest.provides?.lyrics ? '♪' : p.manifest.provides?.cover ? '◫' : '▦');
              })()}
            </div>
            <div className="plugin-card-body">
              <div className="plugin-card-name">
                {p.manifest.name}
                {isNew(p) ? <span className="plugin-badge plugin-badge--new">NEW</span>
                  : p.status === 'incompatible' ? <span className="plugin-badge plugin-badge--incompat">INCOMPATIBLE</span>
                  : p.status === 'error' ? <span className="plugin-badge plugin-badge--error">ERROR</span>
                  : (p.perms.enabled || p.status === 'active') ? <span className="plugin-badge plugin-badge--on">ENABLED</span>
                  : <span className="plugin-badge">OFF</span>}
              </div>
              <div className="plugin-card-meta">{p.id} · {p.manifest.author || 'unknown'} · v{p.manifest.version} · {p.builtin ? 'built-in' : 'user'}</div>
              <div className="plugin-card-desc">{p.manifest.description}{p.lastError ? ` — ${p.lastError}` : ''}</div>
            </div>
            <div className="plugin-card-actions" onClick={(e) => e.stopPropagation()}>
              <ToggleSwitch checked={p.perms.enabled || p.status === 'active'} disabled={p.status === 'incompatible' || p.status === 'error'} onChange={(v) => handleToggle(p, v)} label={p.manifest.name} />
            </div>
          </div>
        ))}
        <div className="plugins-footer">
          <button className="btn btn-secondary" onClick={refresh} disabled={refreshing}>{refreshing ? 'Refreshing…' : 'Refresh'}</button>
          <button className="btn btn-secondary" onClick={() => window.freeplayer.openPluginsDir()}>Open Plugins Folder</button>
          <span className="plugins-dir-path">~/Library/Application Support/FreePlayer/plugins/</span>
        </div>
      </div>

      {pendingPlugin && (
        <div className="confirm-overlay" onClick={() => setPendingPlugin(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 className="confirm-title">Enable “{pendingPlugin.manifest.name}”?</h3>
            <p className="confirm-message">{pendingPlugin.id} v{pendingPlugin.manifest.version} requests the following permissions — read-only grants are pre-checked by default (http is off by default: it can reach localhost/LAN)</p>
            <div className="perm-list">
              {(pendingPlugin.manifest.permissions || []).map((perm) => (
                <label key={perm} className="perm-item">
                  <input
                    type="checkbox"
                    checked={pendingGrants.includes(perm)}
                    onChange={(e) => {
                      const on = e.target.checked;
                      const [domain, level] = perm.split(':');
                      let next = on ? [...pendingGrants, perm] : pendingGrants.filter((x) => x !== perm);
                      if (on && level === 'write' && !next.includes(`${domain}:read`)) next = [...next, `${domain}:read`];
                      if (!on && level === 'read') next = next.filter((x) => x !== `${domain}:write`);
                      setPendingGrants(next);
                    }}
                  />
                  <span className="perm-name">{perm}</span>
                  <span className="perm-desc">{permDesc(perm)}</span>
                </label>
              ))}
            </div>
            <div className="confirm-actions">
              <button className="btn btn-secondary" onClick={() => setPendingPlugin(null)}>Cancel</button>
              <button className="btn btn-primary" onClick={confirmEnable}>Enable with selection</button>
            </div>
          </div>
        </div>
      )}

      {refetchConfirm && (
        <div className="confirm-overlay" onClick={() => setRefetchConfirm(null)}>
          <div className="confirm-dialog" onClick={(e) => e.stopPropagation()}>
            <h3 className="confirm-title">Refetch all {refetchConfirm.kind === 'lyrics' ? 'lyrics' : refetchConfirm.kind === 'cover' ? 'covers' : 'metadata'}?</h3>
            <p className="confirm-message">
              This re-downloads {refetchConfirm.kind === 'lyrics' ? 'lyrics' : refetchConfirm.kind === 'cover' ? 'covers' : 'metadata'} for all {tracks?.length || 0} tracks and overwrites existing data — including lyrics or covers you associated manually.
            </p>
            <div className="confirm-actions">
              <button className="btn btn-secondary" onClick={() => setRefetchConfirm(null)}>Cancel</button>
              <button className="btn btn-primary" onClick={() => {
                const { p: p0, kind: k0 } = refetchConfirm;
                setRefetchConfirm(null);
                handleBackfill(p0, k0, true);
              }}>Refetch All</button>
            </div>
          </div>
        </div>
      )}

      {openDetail && (() => {
        const p = plugins.find((x) => x.id === openDetail);
        if (!p) return null;
        // Auto-fetch drives whatever capabilities the plugin provides,
        // so the label lists them all ("covers & metadata" for musicbrainz).
        const autoCapabilities = ['lyrics', 'cover', 'metadata'].filter((k) => p.manifest.provides?.[k]);
        const autoLabel = `Auto-fetch ${autoCapabilities.map((k) => ({ lyrics: 'lyrics', cover: 'covers', metadata: 'metadata' })[k]).join(' & ')} when missing`;
        return (
          <div className="plugin-detail">
            <div className="plugin-detail-tabs">
              <button className={`plugin-detail-tab${detailTab === 'settings' ? ' plugin-detail-tab--active' : ''}`} onClick={() => setDetailTab('settings')}>Settings</button>
              <button className={`plugin-detail-tab${detailTab === 'permissions' ? ' plugin-detail-tab--active' : ''}`} onClick={() => setDetailTab('permissions')}>Permissions</button>
              <button className={`plugin-detail-tab${detailTab === 'audit' ? ' plugin-detail-tab--active' : ''}`} onClick={() => setDetailTab('audit')}>Audit Log</button>
            </div>
            {detailTab === 'settings' && (
              <div className="plugin-detail-body">
                {(p.manifest.provides?.lyrics || p.manifest.provides?.cover || p.manifest.provides?.metadata) && (
                  <>
                    <div className="playback-row">
                      <div className="playback-label-group">
                        <span className="playback-label">{autoLabel}</span>
                        <span className="playback-hint">
                          Fetch automatically while playing (off by default)
                        </span>
                      </div>
                      <ToggleSwitch
                        checked={!!autoFetch[p.id]}
                        onChange={(val) => handleAutoFetchChange(p.id, val)}
                        label="Auto-fetch"
                      />
                    </div>
                    {['lyrics', 'cover', 'metadata'].filter((k) => p.manifest.provides?.[k]).map((kind) => (
                      <div className="playback-row" key={kind}>
                        <div className="playback-label-group">
                          <span className="playback-label">
                            {kind === 'lyrics' ? 'Fetch All Missing Lyrics'
                              : kind === 'cover' ? 'Fetch All Missing Covers'
                              : 'Fetch All Missing Metadata'}
                          </span>
                          <span className="playback-hint">
                            {backfillProgress && backfillProgress.key === `${p.id}:${kind}`
                              ? `${backfillProgress.fail ? `${backfillProgress.fail} failed · ` : ''}${backfillProgress.noMatch ? `${backfillProgress.noMatch} no match` : ''}`
                              : `Backfill ${kind === 'lyrics' ? 'lyrics' : kind === 'cover' ? 'covers' : 'metadata'} for tracks that are missing them`}
                          </span>
                        </div>
                        <div className="backfill-actions">
                          <button
                            className="btn btn-secondary"
                            disabled={isBackfillRunning() || (backfillProgress && backfillProgress.key === `${p.id}:${kind}`)}
                            onClick={() => handleBackfill(p, kind, false)}
                          >
                            {backfillProgress && backfillProgress.key === `${p.id}:${kind}`
                              ? `Fetching ${backfillProgress.done}/${backfillProgress.total} · ${backfillProgress.ok} saved`
                              : 'Fetch Missing'}
                          </button>
                          <button
                            className="btn btn-secondary"
                            disabled={isBackfillRunning() || (backfillProgress && backfillProgress.key === `${p.id}:${kind}`)}
                            onClick={() => setRefetchConfirm({ p, kind })}
                          >
                            Refetch All
                          </button>
                        </div>
                      </div>
                    ))}
                  </>
                )}
                {p.manifest.provides?.lyrics && (
                  <div className="playback-row">
                    <div className="playback-label-group">
                      <span className="playback-label">Lyrics backend</span>
                      <span className="playback-hint">Source used when fetching lyrics</span>
                    </div>
                    <select className="plugin-select" value={settingsValues.lyricsBackend || 'lrclib-lyrics'} onChange={(e) => { setSettingsValues((s) => ({ ...s, lyricsBackend: e.target.value })); window.freeplayer.setSetting({ key: 'meta.lyricsBackend', value: e.target.value }); }}>
                      {plugins.filter((x) => x.manifest.provides?.lyrics && (x.perms.enabled || x.status === 'active')).map((x) => (
                        <option key={x.id} value={x.id}>{x.manifest.name}{x.id === (settingsValues.lyricsBackend || 'lrclib-lyrics') ? ' (current)' : ''}</option>
                      ))}
                    </select>
                  </div>
                )}
                {p.manifest.provides?.cover && (
                  <div className="playback-row">
                    <div className="playback-label-group">
                      <span className="playback-label">Cover backend</span>
                      <span className="playback-hint">Source used when fetching artwork</span>
                    </div>
                    <select className="plugin-select" value={settingsValues.coverBackend || 'itunes-cover'} onChange={(e) => { setSettingsValues((s) => ({ ...s, coverBackend: e.target.value })); window.freeplayer.setSetting({ key: 'meta.coverBackend', value: e.target.value }); }}>
                      {plugins.filter((x) => x.manifest.provides?.cover && (x.perms.enabled || x.status === 'active')).map((x) => (
                        <option key={x.id} value={x.id}>{x.manifest.name}{x.id === (settingsValues.coverBackend || 'itunes-cover') ? ' (current)' : ''}</option>
                      ))}
                    </select>
                  </div>
                )}
                {p.manifest.provides?.metadata && (
                  <div className="playback-row">
                    <div className="playback-label-group">
                      <span className="playback-label">Metadata backend</span>
                      <span className="playback-hint">Source used for filling in missing track fields</span>
                    </div>
                    <select className="plugin-select" value={settingsValues.metadataBackend || 'musicbrainz-meta'} onChange={(e) => { setSettingsValues((s) => ({ ...s, metadataBackend: e.target.value })); window.freeplayer.setSetting({ key: 'meta.metadataBackend', value: e.target.value }); }}>
                      {plugins.filter((x) => x.manifest.provides?.metadata && (x.perms.enabled || x.status === 'active')).map((x) => (
                        <option key={x.id} value={x.id}>{x.manifest.name}{x.id === (settingsValues.metadataBackend || 'musicbrainz-meta') ? ' (current)' : ''}</option>
                      ))}
                    </select>
                  </div>
                )}
                {(p.manifest.settings || []).map((s) => (
                  <div className="playback-row" key={s.key}>
                    <div className="playback-label-group">
                      <span className="playback-label">{s.label || s.key}</span>
                      {s.description && <span className="playback-hint">{s.description}</span>}
                    </div>
                    {s.type === 'boolean' && (
                      <ToggleSwitch
                        checked={!!(settingsValues[p.id]?.[s.key] ?? s.default)}
                        onChange={(v) => handleSettingChange(p, s, v)}
                        label={s.label || s.key}
                      />
                    )}
                    {s.type === 'number' && (
                      <input
                        className="plugin-select"
                        type="number"
                        min={s.min}
                        max={s.max}
                        value={settingsValues[p.id]?.[s.key] ?? s.default}
                        onChange={(e) => handleSettingChange(p, s, e.target.value === '' ? '' : Number(e.target.value))}
                      />
                    )}
                    {s.type === 'string' && (
                      <input
                        className="plugin-select"
                        type="text"
                        value={settingsValues[p.id]?.[s.key] ?? s.default}
                        onChange={(e) => handleSettingChange(p, s, e.target.value)}
                      />
                    )}
                    {s.type === 'select' && (
                      <select
                        className="plugin-select"
                        value={settingsValues[p.id]?.[s.key] ?? s.default}
                        onChange={(e) => handleSettingChange(p, s, e.target.value)}
                      >
                        {s.options.map((o) => {
                          const opt = typeof o === 'object' && o !== null ? o : { label: String(o), value: String(o) };
                          return <option key={opt.value} value={opt.value}>{opt.label}</option>;
                        })}
                      </select>
                    )}
                  </div>
                ))}
                {p.id === 'diagnostics-log' && (
                  <div className="playback-row">
                    <div className="playback-label-group">
                      <span className="playback-label">Log file location</span>
                      <span className="playback-hint">This fixed location is included in support reports.</span>
                    </div>
                    <code className="plugins-dir-path">{diagnosticsPath || '~/Library/Application Support/FreePlayer/diagnostics/freeplayer-diagnostics.log'}</code>
                  </div>
                )}
                {p.id === 'managed-library' && (
                  <div className="playback-row">
                    <div className="playback-label-group">
                      <span className="playback-label">FPMLIB container</span>
                      <span className="playback-hint">Lossless audio container used for new imports.</span>
                    </div>
                    <code className="plugins-dir-path">{managedContainerPath || 'Select a library directory first'}</code>
                  </div>
                )}
                {(p.manifest.settings || []).length === 0 && !p.manifest.provides?.lyrics && !p.manifest.provides?.cover && !p.manifest.provides?.metadata && (
                  <p className="plugin-empty">This plugin has no settings.</p>
                )}
                {p.manifest.notice && (
                  <p className="plugin-notice">{p.manifest.notice}</p>
                )}
              </div>
            )}
            {detailTab === 'permissions' && (
              <div className="plugin-detail-body perm-list">
                {(p.manifest.permissions || []).map((perm) => (
                  <label key={perm} className="perm-item">
                    <input type="checkbox" checked={p.perms.granted.includes(perm)} onChange={(e) => updateGrants(p, perm, e.target.checked)} />
                    <span className="perm-name">{perm}</span>
                    <span className="perm-desc">{permDesc(perm)}</span>
                  </label>
                ))}
              </div>
            )}
            {detailTab === 'audit' && (
              <div className="plugin-detail-body">
                <div className="audit-log">
                  {registry.getAuditLog(p.id).length === 0 && <p className="plugin-empty">No operations recorded yet.</p>}
                  {registry.getAuditLog(p.id).map((e, i) => (
                    <div key={i} className={`audit-line${e.ok ? ' audit-line--ok' : ' audit-line--err'}`}>
                      <span className="audit-time">{new Date(e.at).toLocaleTimeString()}</span> {e.op} {e.detail}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        );
      })()}
    </div>
  );
}
