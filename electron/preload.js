const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('freeplayer', {
  // Import
  importDialog: () => ipcRenderer.invoke('music:import'),
  scanDirectory: (dirPath) => ipcRenderer.invoke('music:scan', dirPath),
  importFiles: (data) => ipcRenderer.invoke('music:import-files', data),

  // Tracks
  getTracks: (params) => ipcRenderer.invoke('music:get-tracks', params),
  getTrack: (id) => ipcRenderer.invoke('music:get-track', id),
  updateTrack: (data) => ipcRenderer.invoke('music:update-track', data),
  deleteTrack: (id) => ipcRenderer.invoke('music:delete-track', id),
  getTrackCount: () => ipcRenderer.invoke('music:track-count'),
  getTotalDuration: () => ipcRenderer.invoke('music:total-duration'),

  // Playback
  playStart: (trackId) => ipcRenderer.invoke('music:play-start', trackId),
  playEnd: (data) => ipcRenderer.invoke('music:play-end', data),

  // History & Stats
  getPlayHistory: (limit) => ipcRenderer.invoke('music:play-history', limit),
  getStats: () => ipcRenderer.invoke('music:stats'),

  // Cover art
  getCover: (coverPath) => ipcRenderer.invoke('music:get-cover', coverPath),

  // Settings
  getSetting: (key) => ipcRenderer.invoke('music:get-setting', key),
  setSetting: (data) => ipcRenderer.invoke('music:set-setting', data),
  isSetup: () => ipcRenderer.invoke('music:is-setup'),
  selectLibraryDir: () => ipcRenderer.invoke('music:select-library-dir'),
  resetDatabase: () => ipcRenderer.invoke('music:reset-database'),

  // Playlists
  createPlaylist: (data) => ipcRenderer.invoke('playlist:create', data),
  getPlaylists: () => ipcRenderer.invoke('playlist:get-all'),
  addToPlaylist: (data) => ipcRenderer.invoke('playlist:add-track', data),
  getPlaylistTracks: (playlistId) => ipcRenderer.invoke('playlist:get-tracks', playlistId),
  removeFromPlaylist: (data) => ipcRenderer.invoke('playlist:remove-track', data),
  deletePlaylist: (playlistId) => ipcRenderer.invoke('playlist:delete', playlistId),
  renamePlaylist: (data) => ipcRenderer.invoke('playlist:rename', data),

  // System media key listener
  onMediaKey: (callback) => {
    ipcRenderer.on('media-key', (_event, action) => callback(action));
  },
});
