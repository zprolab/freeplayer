export const EVENT_CHANNELS = ['trackChanged', 'playbackChanged'];

export function createEventBus() {
  const listeners = new Map();
  return {
    on(channel, cb) {
      if (!EVENT_CHANNELS.includes(channel)) throw new Error(`unknown event channel: ${channel}`);
      if (!listeners.has(channel)) listeners.set(channel, new Set());
      listeners.get(channel).add(cb);
    },
    off(channel, cb) {
      listeners.get(channel)?.delete(cb);
    },
    emit(channel, payload) {
      if (!EVENT_CHANNELS.includes(channel)) throw new Error(`unknown event channel: ${channel}`);
      for (const cb of listeners.get(channel) || []) {
        try { cb(payload); } catch { /* plugin listener error is isolated */ }
      }
    },
    listeners(channel) {
      return [...(listeners.get(channel) || [])];
    },
  };
}

export function hookTimeout(fn, ms = 15000) {
  return Promise.race([
    Promise.resolve().then(fn),
    new Promise((_, reject) => setTimeout(() => reject(new Error('hook timeout')), ms)),
  ]);
}
