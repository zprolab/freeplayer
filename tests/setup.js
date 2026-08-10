// vitest global setup — mock window.freeplayer IPC bridge
class MockAudioContext {
  constructor() { this.state = 'running'; this.destination = {}; this.currentTime = 0; }
  createAnalyser() { return { fftSize: 2048, smoothingTimeConstant: 0.65, minDecibels: -90, maxDecibels: -10, frequencyBinCount: 1024, connect() {}, disconnect() {} }; }
  createGain() { return { gain: { value: 1, cancelScheduledValues() {}, setTargetAtTime() {} }, connect() {}, disconnect() {} }; }
  createBiquadFilter() {
    return {
      type: '',
      frequency: { value: 0 },
      Q: { value: 0 },
      gain: { value: 0, cancelScheduledValues() {}, setTargetAtTime() {} },
      connect() {}, disconnect() {},
    };
  }
  createMediaElementSource() { return { connect() {}, disconnect() {} }; }
  resume() {}
  close() {}
}

global.window = {
  AudioContext: MockAudioContext,
  webkitAudioContext: MockAudioContext,
  freeplayer: {
    getTracks: async () => [],
    getTrack: async () => null,
    updateTrack: async () => {},
    deleteTrack: async () => {},
    getCover: async () => null,
    getLrc: async () => null,
    saveLrcContent: async () => ({ success: false }),
    saveCover: async () => ({ success: false }),
    httpGetJson: async () => ({ ok: false, status: 404, error: 'not mocked' }),
    getStats: async () => ({ totalTime: 0, totalPlays: 0, uniqueTracksPlayed: 0, topTracks: [], topArtists: [], dailyStats: [] }),
    getPlayHistory: async () => [],
    playStart: async () => 1,
    playEnd: async () => {},
    getSetting: async () => null,
    setSetting: async () => {},
    createPlaylist: async () => ({ lastInsertRowid: 1 }),
    getPlaylists: async () => [],
    getPlaylistTracks: async () => [],
    addToPlaylist: async () => {},
    removeFromPlaylist: async () => {},
    deletePlaylist: async () => {},
    renamePlaylist: async () => {},
    isSetup: async () => ({ setup: true, libraryDir: '/test/lib' }),
    resetDatabase: async () => {},
    importDialog: async () => ({ canceled: true }),
    scanDirectory: async () => [],
    importFiles: async () => ({ imported: 0, errors: [] }),
    selectLibraryDir: async () => ({ canceled: true }),
    getTotalDuration: async () => 0,
    listPlugins: async () => [],
    readPluginFile: async () => null,
    uninstallPlugin: async () => {},
    openPluginsDir: async () => {},
  },
};
