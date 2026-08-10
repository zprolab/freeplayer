import { useState, useEffect, useCallback } from 'react';
import ToggleSwitch from './ToggleSwitch';

const STATUS_LABEL = { enabled: 'ENABLED', disabled: 'OFF', active: 'ACTIVE', error: 'ERROR', incompatible: 'INCOMPATIBLE' };

const PERM_DESC = {
  http: 'Make network requests (GET)',
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

function permDesc(perm) {
  return PERM_DESC[perm] || 'Access requested by this plugin';
}

export default function PluginPage({ registry, onRegistryChange }) {
  const [plugins, setPlugins] = useState([]);
  const [refreshing, setRefreshing] = useState(false);
  const [pendingPlugin, setPendingPlugin] = useState(null); // 权限弹窗对象 { id, manifest }
  const [pendingGrants, setPendingGrants] = useState([]);
  const [openDetail, setOpenDetail] = useState(null); // 详情面板插件 id
  const [detailTab, setDetailTab] = useState('settings');
  const [settingsValues, setSettingsValues] = useState({});

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

  // 后端下拉初始化：读取已存 meta.lyricsBackend / meta.coverBackend，
  // 与 metadataRegistry.backendFor 的取值保持一致（未加载/无存值时回落默认）。
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [lyrics, cover] = await Promise.all([
          window.freeplayer.getSetting('meta.lyricsBackend'),
          window.freeplayer.getSetting('meta.coverBackend'),
        ]);
        if (cancelled) return;
        setSettingsValues((s) => ({
          ...s,
          lyricsBackend: lyrics || s.lyricsBackend,
          coverBackend: cover || s.coverBackend,
        }));
      } catch {
        // 读取失败则保持默认值
      }
    })();
    return () => { cancelled = true; };
  }, []);

  async function handleToggle(p, enabled) {
    if (enabled) {
      if (isNew(p)) { setPendingPlugin(p); setPendingGrants((p.manifest.permissions || []).filter((x) => x.endsWith(':read') || x === 'http')); return; }
      // 重新启用：保留既有 granted（disable 不清空），避免静默降权
      await registry.enable(p.id, p.perms.granted);
    } else {
      await registry.disable(p.id);
    }
    await refresh();
  }

  async function confirmEnable() {
    await registry.enable(pendingPlugin.id, pendingGrants);
    setOpenDetail(pendingPlugin.id); setDetailTab('settings');
    setPendingPlugin(null);
    await refresh();
  }

  async function updateGrants(p, perm, on) {
    const [domain, level] = perm.split(':');
    let next = on ? [...p.perms.granted, perm] : p.perms.granted.filter((x) => x !== perm);
    if (on && level === 'write' && !next.includes(`${domain}:read`)) next = [...next, `${domain}:read`];
    if (!on && level === 'read') next = next.filter((x) => x !== `${domain}:write`);
    await registry.enable(p.id, next);
    await refresh();
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
            <div className="plugin-card-avatar">{p.manifest.provides?.lyrics ? '♪' : p.manifest.provides?.cover ? '◫' : '▦'}</div>
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
              <ToggleSwitch checked={p.perms.enabled || p.status === 'active'} disabled={p.status === 'incompatible'} onChange={(v) => handleToggle(p, v)} label={p.manifest.name} />
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
            <p className="confirm-message">{pendingPlugin.id} v{pendingPlugin.manifest.version} requests the following permissions — read-only is pre-checked by default</p>
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

      {openDetail && (() => {
        const p = plugins.find((x) => x.id === openDetail);
        if (!p) return null;
        return (
          <div className="plugin-detail">
            <div className="plugin-detail-tabs">
              <button className={`plugin-detail-tab${detailTab === 'settings' ? ' plugin-detail-tab--active' : ''}`} onClick={() => setDetailTab('settings')}>Settings</button>
              <button className={`plugin-detail-tab${detailTab === 'permissions' ? ' plugin-detail-tab--active' : ''}`} onClick={() => setDetailTab('permissions')}>Permissions</button>
              <button className={`plugin-detail-tab${detailTab === 'audit' ? ' plugin-detail-tab--active' : ''}`} onClick={() => setDetailTab('audit')}>Audit Log</button>
            </div>
            {detailTab === 'settings' && (
              <div className="plugin-detail-body">
                {p.manifest.provides?.lyrics && (
                  <div className="plugin-field">
                    <label>Lyrics backend</label>
                    <select className="plugin-select" value={settingsValues.lyricsBackend || 'lrclib-lyrics'} onChange={(e) => { setSettingsValues((s) => ({ ...s, lyricsBackend: e.target.value })); window.freeplayer.setSetting({ key: 'meta.lyricsBackend', value: e.target.value }); }}>
                      {plugins.filter((x) => x.manifest.provides?.lyrics && (x.perms.enabled || x.status === 'active')).map((x) => (
                        <option key={x.id} value={x.id}>{x.manifest.name}{x.id === (settingsValues.lyricsBackend || 'lrclib-lyrics') ? ' (current)' : ''}</option>
                      ))}
                    </select>
                  </div>
                )}
                {p.manifest.provides?.cover && (
                  <div className="plugin-field">
                    <label>Cover backend</label>
                    <select className="plugin-select" value={settingsValues.coverBackend || 'itunes-cover'} onChange={(e) => { setSettingsValues((s) => ({ ...s, coverBackend: e.target.value })); window.freeplayer.setSetting({ key: 'meta.coverBackend', value: e.target.value }); }}>
                      {plugins.filter((x) => x.manifest.provides?.cover && (x.perms.enabled || x.status === 'active')).map((x) => (
                        <option key={x.id} value={x.id}>{x.manifest.name}{x.id === (settingsValues.coverBackend || 'itunes-cover') ? ' (current)' : ''}</option>
                      ))}
                    </select>
                  </div>
                )}
                {(p.manifest.settings || []).map((s) => (
                  <div className="plugin-field" key={s.key}>
                    <label>{s.label || s.key}</label>
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
                {(p.manifest.settings || []).length === 0 && !p.manifest.provides?.lyrics && !p.manifest.provides?.cover && (
                  <p className="plugin-empty">This plugin has no settings.</p>
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
