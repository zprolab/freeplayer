// vitest global setup — mock window.freeplayer IPC bridge
global.window = {
  AudioContext: class MockAudioContext {
    constructor() { this.state = 'running'; this.destination = {}; }
    createAnalyser() { return { fftSize: 2048, smoothingTimeConstant: 0.65, minDecibels: -90, maxDecibels: -10, frequencyBinCount: 1024, connect() {}, disconnect() {} }; }
    createGain() { return { gain: { value: 1, cancelScheduledValues() {}, setTargetAtTime() {} }, connect() {}, disconnect() {} }; }
    createMediaElementSource() { return { connect() {}, disconnect() {} }; }
    resume() {}
    close() {}
  },
  webkitAudioContext: class MockAudioContext {
    constructor() { this.state = 'running'; this.destination = {}; }
    createAnalyser() { return { fftSize: 2048, smoothingTimeConstant: 0.65, minDecibels: -90, maxDecibels: -10, frequencyBinCount: 1024, connect() {}, disconnect() {} }; }
    createGain() { return { gain: { value: 1, cancelScheduledValues() {}, setTargetAtTime() {} }, connect() {}, disconnect() {} }; }
    createMediaElementSource() { return { connect() {}, disconnect() {} }; }
    resume() {}
    close() {}
  },
  freeplayer: {
    getTracks: async () => [],
    getTrack: async () => null,
    updateTrack: async () => {},
    deleteTrack: async () => {},
    getCover: async () => null,
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
  },
};
