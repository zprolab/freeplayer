import { describe, it, expect, vi, beforeEach } from 'vitest';

// Lightweight react harness (same pattern as useAutoMeta.test.js): the hook
// swaps in useEffect/useRef/useState driven by call order, so the settings
// load effect and the toggle handlers can be exercised without a DOM renderer.
const { hookState } = vi.hoisted(() => ({
  hookState: { effects: [], refs: [], refIndex: 0, states: [], stateIndex: 0 },
}));

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    useEffect: (cb) => { hookState.effects.push(cb); },
    useRef: (init) => {
      const idx = hookState.refIndex++;
      if (!hookState.refs[idx]) hookState.refs[idx] = { current: init };
      return hookState.refs[idx];
    },
    useState: (init) => {
      const idx = hookState.stateIndex++;
      if (!hookState.states[idx]) hookState.states[idx] = { value: init, setter: () => {} };
      return [hookState.states[idx].value, (v) => { hookState.states[idx].value = v; }];
    },
  };
});

import { useTraySettings } from '../src/hooks/useTraySettings';

function reset() {
  hookState.effects = [];
  hookState.refs = [];
  hookState.refIndex = 0;
  hookState.states = [];
  hookState.stateIndex = 0;
}

let handlers;
function mount() {
  reset();
  handlers = useTraySettings();
}

// Re-call the hook with the same state slots: returns fresh handler closures
// (mirrors React re-renders) without re-running the load effect.
function update() {
  hookState.effects = [];
  hookState.refIndex = 0;
  hookState.stateIndex = 0;
  handlers = useTraySettings();
}

function values() {
  return {
    settingsLoaded: hookState.states[0].value,
    trayEnabled: hookState.states[1].value,
    trayNotify: hookState.states[2].value,
    startOnBoot: hookState.states[3].value,
    startHidden: hookState.states[4].value,
    settingsError: hookState.states[5].value,
  };
}

async function flush() {
  await new Promise((r) => setTimeout(r, 0));
  await new Promise((r) => setTimeout(r, 0));
}

beforeEach(() => {
  reset();
  window.freeplayer.getSetting = vi.fn(async () => null);
  window.freeplayer.setSetting = vi.fn(async () => true);
  window.freeplayer.getLoginItemSettings = vi.fn(async () => ({ openAtLogin: false, openAsHidden: false }));
  window.freeplayer.setLoginItemSettings = vi.fn(async () => ({ ok: true }));
});

describe('useTraySettings', () => {
  describe('loading', () => {
    it('loads each key from its own source and enables the page when settled', async () => {
      window.freeplayer.getSetting = vi.fn(async (k) => (
        k === 'tray_enabled' ? '1' : k === 'start_hidden' ? '1' : null
      ));
      window.freeplayer.getLoginItemSettings = vi.fn(async () => ({ openAtLogin: true, openAsHidden: true }));
      mount();
      hookState.effects[0]();
      await flush();
      expect(values().settingsLoaded).toBe(true);
      expect(values().trayEnabled).toBe(true);
      expect(values().startHidden).toBe(true);
      expect(values().startOnBoot).toBe(true);
      expect(values().trayNotify).toBe(false);
    });

    it('does not zero other toggles when one key fails to load', async () => {
      window.freeplayer.getSetting = vi.fn(async (k) => {
        if (k === 'tray_notify') throw new Error('db busy');
        return k === 'tray_enabled' ? '1' : null;
      });
      window.freeplayer.getLoginItemSettings = vi.fn(async () => ({ openAtLogin: true, openAsHidden: false }));
      mount();
      hookState.effects[0]();
      await flush();
      expect(values().trayEnabled).toBe(true);
      expect(values().startOnBoot).toBe(true);
      expect(values().trayNotify).toBe(false);
      expect(values().settingsLoaded).toBe(true);
    });
  });

  describe('tray_enabled', () => {
    it('flips only after persistence confirms (no optimistic flip)', async () => {
      mount();
      const p = handlers.changeTrayEnabled(true);
      expect(values().trayEnabled).toBe(false);
      await p;
      expect(values().trayEnabled).toBe(true);
      expect(window.freeplayer.setSetting).toHaveBeenCalledWith({ key: 'tray_enabled', value: true });
    });

    it('keeps the stored value and reports an error when the write fails', async () => {
      window.freeplayer.setSetting = vi.fn(async () => false);
      window.freeplayer.getSetting = vi.fn(async (k) => (k === 'tray_enabled' ? '0' : null));
      mount();
      await handlers.changeTrayEnabled(true);
      expect(values().trayEnabled).toBe(false);
      expect(values().settingsError).toBeTruthy();
    });

    it('re-syncs from the persisted value when the write fails after a previous write landed', async () => {
      let call = 0;
      window.freeplayer.setSetting = vi.fn(async () => (++call === 1 ? true : false));
      window.freeplayer.getSetting = vi.fn(async (k) => (k === 'tray_enabled' ? '1' : null));
      mount();
      await handlers.changeTrayEnabled(true);
      update(); // fresh closures for the second attempt
      await handlers.changeTrayEnabled(false);
      expect(values().trayEnabled).toBe(true); // persisted value is still 1
      expect(values().settingsError).toBeTruthy();
    });

    it('a stale failure does not clobber a newer successful write', async () => {
      let resolveFirst;
      let call = 0;
      window.freeplayer.setSetting = vi.fn(async () => {
        call++;
        if (call === 1) return new Promise((r) => { resolveFirst = r; });
        return true;
      });
      mount();
      const first = handlers.changeTrayEnabled(true);
      const second = handlers.changeTrayEnabled(false);
      await second;
      expect(values().trayEnabled).toBe(false);
      resolveFirst(false); // first write fails after the second succeeded
      await first;
      expect(values().trayEnabled).toBe(false);
      expect(values().settingsError).toBeNull();
    });

    it('a failed resync READ does not flip the switch off (DB may still hold true)', async () => {
      let call = 0;
      window.freeplayer.setSetting = vi.fn(async () => (++call === 1 ? true : false));
      window.freeplayer.getSetting = vi.fn(async (k) => {
        if (k !== 'tray_enabled') return null;
        if (call <= 1) return '1';
        throw new Error('db busy'); // resync read after the failed second write
      });
      mount();
      await handlers.changeTrayEnabled(true);
      update(); // fresh closures for the second attempt
      await handlers.changeTrayEnabled(false);
      expect(values().trayEnabled).toBe(true); // kept, NOT forced to false
      expect(values().settingsError).toBeTruthy();
    });

    it('keeps per-key generations separate (a write to another key is not "stale")', async () => {
      mount();
      const p1 = handlers.changeTrayEnabled(true);
      await handlers.changeTrayNotify(true); // bumps a different key's counter
      await p1;
      expect(values().trayEnabled).toBe(true);
      expect(values().trayNotify).toBe(true);
    });
  });

  describe('tray_notify', () => {
    it('persists and flips on success', async () => {
      mount();
      await handlers.changeTrayNotify(true);
      expect(values().trayNotify).toBe(true);
      expect(window.freeplayer.setSetting).toHaveBeenCalledWith({ key: 'tray_notify', value: true });
    });

    it('keeps the stored value on failure', async () => {
      window.freeplayer.setSetting = vi.fn(async () => false);
      window.freeplayer.getSetting = vi.fn(async (k) => (k === 'tray_notify' ? '0' : null));
      mount();
      await handlers.changeTrayNotify(true);
      expect(values().trayNotify).toBe(false);
      expect(values().settingsError).toBeTruthy();
    });
  });

  describe('start_on_boot (native login item is the source of truth)', () => {
    it('flips and writes the DB only after the native login item accepts', async () => {
      mount();
      await handlers.changeStartOnBoot(true);
      expect(values().startOnBoot).toBe(true);
      expect(window.freeplayer.setLoginItemSettings).toHaveBeenCalledWith({ openAtLogin: true, openAsHidden: false });
      expect(window.freeplayer.setSetting).toHaveBeenCalledWith({ key: 'start_on_boot', value: true });
    });

    it('does not flip and does not write the DB when the native call fails', async () => {
      window.freeplayer.setLoginItemSettings = vi.fn(async () => ({ ok: false }));
      mount();
      await handlers.changeStartOnBoot(true);
      expect(values().startOnBoot).toBe(false);
      expect(window.freeplayer.setSetting).not.toHaveBeenCalled();
      expect(values().settingsError).toBeTruthy();
    });

    it('passes the current hidden preference along', async () => {
      window.freeplayer.getSetting = vi.fn(async (k) => (k === 'start_hidden' ? '1' : null));
      mount();
      hookState.effects[0]();
      await flush();
      update();
      await handlers.changeStartOnBoot(true);
      expect(window.freeplayer.setLoginItemSettings).toHaveBeenCalledWith({ openAtLogin: true, openAsHidden: true });
    });
  });

  describe('start_hidden', () => {
    it('persists the DB value and passes openAsHidden to the native call', async () => {
      mount();
      await handlers.changeStartHidden(true);
      expect(values().startHidden).toBe(true);
      expect(window.freeplayer.setSetting).toHaveBeenCalledWith({ key: 'start_hidden', value: '1' });
      expect(window.freeplayer.setLoginItemSettings).toHaveBeenCalledWith({ openAtLogin: false, openAsHidden: true });
    });

    it('accepts the change when the DB write succeeds even if the native call is best-effort', async () => {
      window.freeplayer.setLoginItemSettings = vi.fn(async () => ({ ok: false }));
      mount();
      await handlers.changeStartHidden(true);
      expect(values().startHidden).toBe(true);
      expect(values().settingsError).toBeNull();
    });

    it('keeps the stored value on DB write failure', async () => {
      window.freeplayer.setSetting = vi.fn(async () => false);
      window.freeplayer.getSetting = vi.fn(async (k) => (k === 'start_hidden' ? '0' : null));
      mount();
      await handlers.changeStartHidden(true);
      expect(values().startHidden).toBe(false);
      expect(values().settingsError).toBeTruthy();
    });
  });
});
