export const EVENT_CHANNELS = ['trackChanged', 'playbackChanged'];

// Owner-aware event bus. Listeners may be registered with an owner id so
// that a whole plugin's listeners can be dropped in one call
// (removeOwner) when it is disabled/uninstalled — preventing zombie
// listeners from reactivated plugins firing twice.
export function createEventBus() {
  const listeners = new Map(); // channel -> Set<{ cb, owner }>
  return {
    on(channel, cb, ownerId) {
      if (!EVENT_CHANNELS.includes(channel)) throw new Error(`unknown event channel: ${channel}`);
      if (typeof cb !== 'function') return;
      if (!listeners.has(channel)) listeners.set(channel, new Set());
      listeners.get(channel).add({ cb, owner: ownerId });
    },
    off(channel, cb) {
      const set = listeners.get(channel);
      if (!set) return;
      for (const entry of set) if (entry.cb === cb) set.delete(entry);
    },
    removeOwner(ownerId) {
      for (const set of listeners.values()) {
        for (const entry of set) if (entry.owner === ownerId) set.delete(entry);
      }
    },
    emit(channel, payload) {
      if (!EVENT_CHANNELS.includes(channel)) throw new Error(`unknown event channel: ${channel}`);
      for (const entry of listeners.get(channel) || []) {
        try { entry.cb(payload); } catch { /* plugin listener error is isolated */ }
      }
    },
    listeners(channel) {
      return [...(listeners.get(channel) || [])].map((entry) => entry.cb);
    },
  };
}

// Host-side hook timeout. The timer is always cleared once the race settles
// (fast hook or timeout). NOTE: this is host-side containment only — the
// plugin's promise keeps running in the worker after a timeout; the worker
// sandbox makes that safe (it cannot touch the host), and the pending
// result, if any, is simply dropped when the seq is no longer awaited.
export function hookTimeout(fn, ms = 15000) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error('hook timeout')), ms);
  });
  return Promise.race([Promise.resolve().then(fn), timeout])
    .finally(() => clearTimeout(timer));
}
