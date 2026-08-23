import { useEffect, useRef, useState } from 'react';

const SAVE_FAILED = 'Could not save this setting — the change was not applied. Please try again.';

// Coerce a DB setting (may be boolean, number, or string) to a boolean
const coerceBool = (val) => {
  if (val === true || val === 1) return true;
  if (val === false || val === 0 || val == null) return false;
  if (typeof val === 'string') {
    const s = val.toLowerCase();
    return s === 'true' || s === '1' || s === '1.0' || s === 'yes' || s === 'on';
  }
  return false;
};

// Tray / launch toggles with verified persistence:
// - UI state only flips AFTER the native write confirms, so a failing write
//   can never leave the switch and the stored setting out of sync.
// - Every key loads independently, so one failing read cannot zero the rest.
// - A per-key generation guard means a stale (older) write result for a key
//   never clobbers a newer one when the user toggles quickly.
export function useTraySettings() {
  const [settingsLoaded, setSettingsLoaded] = useState(false);
  const [trayEnabled, setTrayEnabled] = useState(false);
  const [trayNotify, setTrayNotify] = useState(false);
  const [startOnBoot, setStartOnBoot] = useState(false);
  const [startHidden, setStartHidden] = useState(false);
  const [settingsError, setSettingsError] = useState(null);
  const genRef = useRef({});

  const nextGen = (key) => (genRef.current[key] = (genRef.current[key] || 0) + 1);
  const isLatest = (key, gen) => gen === genRef.current[key];

  useEffect(() => {
    let cancelled = false;
    const loadTrayEnabled = window.freeplayer.getSetting('tray_enabled')
      .then((v) => { if (!cancelled) setTrayEnabled(coerceBool(v)); })
      .catch(() => {});
    const loadTrayNotify = window.freeplayer.getSetting('tray_notify')
      .then((v) => { if (!cancelled) setTrayNotify(coerceBool(v)); })
      .catch(() => {});
    const loadStartHidden = window.freeplayer.getSetting('start_hidden')
      .then((v) => { if (!cancelled) setStartHidden(coerceBool(v)); })
      .catch(() => {});
    const loadStartOnBoot = window.freeplayer.getLoginItemSettings()
      .then((login) => { if (!cancelled) setStartOnBoot(!!(login && login.openAtLogin)); })
      .catch(() => {});
    Promise.allSettled([loadTrayEnabled, loadTrayNotify, loadStartHidden, loadStartOnBoot])
      .then(() => { if (!cancelled) setSettingsLoaded(true); });
    return () => { cancelled = true; };
  }, []);

  // Re-read the persisted value and sync the UI state with it. Used after a
  // failed write so the switch always shows what is actually stored. When the
  // read itself fails, leave the current UI state alone: the DB may still hold
  // the written value, and forcing the switch to false would lie about it.
  const resync = async (key, gen, readPersisted, setState) => {
    if (!isLatest(key, gen)) return;
    let actual;
    try {
      actual = await readPersisted();
    } catch {
      return;
    }
    if (isLatest(key, gen)) setState(actual);
  };

  // Write first, then flip the UI: a failed write surfaces an error and
  // re-syncs the switch from the persisted value instead of lying.
  const persist = async (key, gen, write, resyncState) => {
    setSettingsError(null);
    const ok = await write().catch(() => false);
    if (ok === false) {
      // A stale (older) failure must not surface: a newer write for this key
      // owns the UI and may have already succeeded.
      if (!isLatest(key, gen)) return false;
      setSettingsError(SAVE_FAILED);
      await resyncState();
      return false;
    }
    return true;
  };

  const changeTrayEnabled = async (val) => {
    const key = 'tray_enabled';
    const gen = nextGen(key);
    const ok = await persist(key, gen,
      () => window.freeplayer.setSetting({ key, value: val }),
      () => resync(key, gen,
        () => window.freeplayer.getSetting(key),
        (v) => { if (isLatest(key, gen)) setTrayEnabled(coerceBool(v)); }));
    if (ok && isLatest(key, gen)) setTrayEnabled(val);
  };

  const changeTrayNotify = async (val) => {
    const key = 'tray_notify';
    const gen = nextGen(key);
    const ok = await persist(key, gen,
      () => window.freeplayer.setSetting({ key, value: val }),
      () => resync(key, gen,
        () => window.freeplayer.getSetting(key),
        (v) => { if (isLatest(key, gen)) setTrayNotify(coerceBool(v)); }));
    if (ok && isLatest(key, gen)) setTrayNotify(val);
  };

  // The OS login item is the source of truth for startOnBoot: flip the UI and
  // mirror the DB only when the native registration/unregistration succeeded.
  const changeStartOnBoot = async (val) => {
    const key = 'start_on_boot';
    const gen = nextGen(key);
    setSettingsError(null);
    const native = await window.freeplayer.setLoginItemSettings({ openAtLogin: val, openAsHidden: startHidden })
      .catch(() => null);
    if (!native || native.ok === false) {
      if (!isLatest(key, gen)) return;
      setSettingsError(SAVE_FAILED);
      await resync(key, gen,
        () => window.freeplayer.getLoginItemSettings().then((l) => (l && l.openAtLogin ? '1' : '0')),
        (v) => { if (isLatest(key, gen)) setStartOnBoot(coerceBool(v)); });
      return;
    }
    const ok = await window.freeplayer.setSetting({ key, value: val }).catch(() => false);
    if (ok === false) {
      if (!isLatest(key, gen)) return;
      setSettingsError(SAVE_FAILED);
      await resync(key, gen,
        () => window.freeplayer.getSetting(key),
        () => {}); // keep the native-confirmed state; the DB mirror is best-effort
      return;
    }
    if (isLatest(key, gen)) setStartOnBoot(val);
  };

  // The DB start_hidden value is what the shell consults at launch, so the DB
  // write is authoritative; the native call only mirrors openAsHidden.
  const changeStartHidden = async (val) => {
    const key = 'start_hidden';
    const gen = nextGen(key);
    const ok = await persist(key, gen,
      () => window.freeplayer.setSetting({ key, value: val ? '1' : '0' }),
      () => resync(key, gen,
        () => window.freeplayer.getSetting(key),
        (v) => { if (isLatest(key, gen)) setStartHidden(coerceBool(v)); }));
    if (!ok) return;
    window.freeplayer.setLoginItemSettings({ openAtLogin: startOnBoot, openAsHidden: val }).catch(() => {});
    if (isLatest(key, gen)) setStartHidden(val);
  };

  return {
    settingsLoaded,
    trayEnabled,
    trayNotify,
    startOnBoot,
    startHidden,
    settingsError,
    changeTrayEnabled,
    changeTrayNotify,
    changeStartOnBoot,
    changeStartHidden,
  };
}
