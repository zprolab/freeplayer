const { app, BrowserWindow, ipcMain, dialog, protocol, globalShortcut } = require('electron');
const path = require('path');
const fs = require('fs');
const {
  initDatabase,
  closeDatabase,
  insertTrack,
  getAllTracks,
  getTrackById,
  updateTrack,
  deleteTrack,
  getTrackCount,
  startPlaySession,
  endPlaySession,
  getPlayHistory,
  getListeningStats,
  createPlaylist,
  getAllPlaylists,
  addTrackToPlaylist,
  addTracksToPlaylist,
  setPlaylistTracks,
  getPlaylistTracks,
  removeTrackFromPlaylist,
  deletePlaylist,
  renamePlaylist,
  setTrackLrc,
  getTrackLrc,
  clearTrackLrc,
  getSetting,
  resetDatabase,
  setSetting,
} = require('./database');

const isDev = !app.isPackaged;

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 600,
    title: 'FreePlayer',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 14 },
    backgroundColor: '#1f1f23',
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
  } else {
    mainWindow.loadFile(path.join(__dirname, '..', 'dist', 'index.html'));
  }
}

function registerProtocol() {
  const mimeTypes = {
    '.mp3': 'audio/mpeg',
    '.flac': 'audio/flac',
    '.wav': 'audio/wav',
    '.ogg': 'audio/ogg',
    '.m4a': 'audio/mp4',
    '.aac': 'audio/aac',
    '.wma': 'audio/x-ms-wma',
    '.opus': 'audio/opus',
    '.aiff': 'audio/aiff',
    '.ape': 'audio/ape',
  };

  protocol.handle('media', (request) => {
    const rawPath = decodeURIComponent(request.url.slice('media://'.length));
    const filePath = path.resolve(rawPath);

    // Path traversal protection: reject paths that escape the library directory
    const libraryDir = getSetting('library_dir', '');
    if (libraryDir && !filePath.startsWith(path.resolve(libraryDir) + path.sep)
        && filePath !== path.resolve(libraryDir)) {
      return new Response('Forbidden', { status: 403 });
    }

    try {
      if (!fs.existsSync(filePath)) {
        return new Response('Not Found', { status: 404 });
      }
      const stat = fs.statSync(filePath);
      const ext = path.extname(filePath).toLowerCase();
      const mimeType = mimeTypes[ext] || 'audio/mpeg';
      const fileSize = stat.size;

      // Handle range requests for seeking
      const rangeHeader = request.headers.get('range');
      if (rangeHeader) {
        const parts = rangeHeader.replace(/bytes=/, '').split('-');
        const start = parseInt(parts[0], 10);
        const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
        const chunkSize = end - start + 1;
        const buffer = Buffer.alloc(chunkSize);
        const fd = fs.openSync(filePath, 'r');
        try {
          fs.readSync(fd, buffer, 0, chunkSize, start);
        } finally {
          fs.closeSync(fd);
        }
        return new Response(buffer, {
          status: 206,
          headers: {
            'Content-Type': mimeType,
            'Content-Length': String(chunkSize),
            'Content-Range': `bytes ${start}-${end}/${fileSize}`,
            'Accept-Ranges': 'bytes',
          },
        });
      }

      // Full file response
      const data = fs.readFileSync(filePath);
      return new Response(data, {
        status: 200,
        headers: {
          'Content-Type': mimeType,
          'Content-Length': String(fileSize),
          'Accept-Ranges': 'bytes',
        },
      });
    } catch (err) {
      console.error('media protocol error:', err);
      return new Response('Internal Error', { status: 500 });
    }
  });
}

// ── IPC Handlers ──

function setupIPC() {
  // Import: select source directory and copy files to library
  ipcMain.handle('music:import', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openDirectory'],
      title: 'Select directory containing music files',
    });

    if (result.canceled || result.filePaths.length === 0) {
      return { canceled: true };
    }

    const sourceDir = result.filePaths[0];

    // Get or ask for library directory
    let libraryDir = getSetting('library_dir');
    if (!libraryDir) {
      const libResult = await dialog.showOpenDialog(mainWindow, {
        properties: ['openDirectory', 'createDirectory'],
        title: 'Select destination library directory',
      });
      if (libResult.canceled || libResult.filePaths.length === 0) {
        return { canceled: true };
      }
      libraryDir = libResult.filePaths[0];
      setSetting('library_dir', libraryDir);
    }

    return { sourceDir, libraryDir, canceled: false };
  });

  // Scan directory for music files
  ipcMain.handle('music:scan', async (_event, dirPath) => {
    const supportedFormats = ['.mp3', '.flac', '.wav', '.ogg', '.m4a', '.aac', '.wma', '.opus', '.aiff', '.ape'];
    const files = [];

    async function scanRecursive(dir) {
      const entries = fs.readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
          await scanRecursive(fullPath);
        } else if (entry.isFile()) {
          const ext = path.extname(entry.name).toLowerCase();
          if (supportedFormats.includes(ext)) {
            files.push(fullPath);
          }
        }
      }
    }

    await scanRecursive(dirPath);
    return files;
  });

  // Import files to library
  ipcMain.handle('music:import-files', async (_event, { files, libraryDir }) => {
    const musicMetadata = await import('music-metadata');
    const importMode = getSetting('import_mode', 'copy'); // 'copy' | 'symlink'
    const results = { imported: 0, skipped: 0, errors: [] };

    for (const filePath of files) {
      try {
        // Read metadata
        const metadata = await musicMetadata.parseFile(filePath);
        const common = metadata.common;
        const format = metadata.format;

        const ext = path.extname(filePath).toLowerCase();
        const baseName = path.basename(filePath);

        // Determine artist and album for folder structure
        const artist = (common.artists && common.artists[0]) ||
                        common.artist || 'Unknown Artist';
        const album = common.album || 'Unknown Album';
        const safeArtist = artist.replace(/[/\\?%*:|"<>]/g, '_');
        const safeAlbum = album.replace(/[/\\?%*:|"<>]/g, '_');

        // Create target directory
        const artistDir = path.join(libraryDir, safeArtist);
        const albumDir = path.join(artistDir, safeAlbum);
        if (!fs.existsSync(albumDir)) {
          fs.mkdirSync(albumDir, { recursive: true });
        }

        // Copy or symlink file to library
        const targetPath = path.join(albumDir, baseName);
        if (!fs.existsSync(targetPath)) {
          if (importMode === 'symlink') {
            fs.symlinkSync(filePath, targetPath);
          } else {
            fs.copyFileSync(filePath, targetPath);
          }
        }

        const fileSize = fs.statSync(targetPath).size;

        // Duration: try multiple sources, music-metadata v10 may place it differently
        let duration = format.duration;
        if (!duration && format.numberOfSamples && format.sampleRate) {
          duration = format.numberOfSamples / format.sampleRate;
        }

        // Extract cover art
        let coverPath = null;
        if (common.picture && common.picture.length > 0) {
          const picture = common.picture[0];
          const coverDir = path.join(albumDir, '.covers');
          if (!fs.existsSync(coverDir)) {
            fs.mkdirSync(coverDir, { recursive: true });
          }
          const coverExt = picture.format === 'image/jpeg' ? 'jpg' :
                           picture.format === 'image/png' ? 'png' :
                           picture.format === 'image/webp' ? 'webp' : 'jpg';
          const coverFileName = `cover.${coverExt}`;
          coverPath = path.join(coverDir, coverFileName);
          if (!fs.existsSync(coverPath)) {
            fs.writeFileSync(coverPath, picture.data);
          }
        }

        // ReplayGain tags (for loudness normalization)
        const rgGain = common.replaygain_track_gain?.dB ?? common.replaygain_track_gain;
        const rgPeak = common.replaygain_track_peak;

        // Insert track data
        const trackData = {
          title: common.title || baseName.replace(ext, ''),
          artist,
          album,
          track_number: common.track?.no || null,
          disc_number: common.disk?.no || null,
          genre: (common.genre && common.genre[0]) || null,
          year: common.year || null,
          duration: duration || 0,
          file_path: targetPath,
          file_name: baseName,
          file_size: fileSize,
          file_format: format.container || ext.replace('.', ''),
          bitrate: format.bitrate ? Math.round(format.bitrate / 1000) : null,
          sample_rate: format.sampleRate || null,
          channels: format.numberOfChannels || null,
          cover_path: coverPath,
          replaygain_gain: rgGain != null ? rgGain : 0,
          replaygain_peak: rgPeak != null ? rgPeak : 0,
        };

        insertTrack(trackData);
        results.imported++;
      } catch (err) {
        results.errors.push({ file: filePath, error: err.message });
      }
    }

    return results;
  });

  // Get all tracks
  ipcMain.handle('music:get-tracks', (_event, { search, sortBy, sortDir } = {}) => {
    return getAllTracks(search, sortBy, sortDir);
  });

  // Get single track
  ipcMain.handle('music:get-track', (_event, id) => {
    return getTrackById(id);
  });

  // Update track metadata
  ipcMain.handle('music:update-track', (_event, { id, fields }) => {
    return updateTrack(id, fields);
  });

  // Delete track
  ipcMain.handle('music:delete-track', async (_event, id) => {
    const track = getTrackById(id);
    if (track) {
      // Clean up cover file if no other track references it
      if (track.cover_path && fs.existsSync(track.cover_path)) {
        const db = require('./database').getDatabase();
        const refCount = db.prepare(
          'SELECT COUNT(*) as count FROM tracks WHERE cover_path = ?'
        ).get(track.cover_path).count;
        if (refCount <= 1) {
          fs.unlinkSync(track.cover_path);
        }
      }
      // Delete file from library
      if (fs.existsSync(track.file_path)) {
        fs.unlinkSync(track.file_path);
      }
      deleteTrack(id);
    }
    return { success: true };
  });

  // Get track count
  ipcMain.handle('music:track-count', () => {
    return getTrackCount();
  });

  // Start play session
  ipcMain.handle('music:play-start', (_event, trackId) => {
    return startPlaySession(trackId);
  });

  // End play session
  ipcMain.handle('music:play-end', (_event, { sessionId, durationSeconds, playPercentage }) => {
    endPlaySession(sessionId, durationSeconds, playPercentage);
    return { success: true };
  });

  // Get play history
  ipcMain.handle('music:play-history', (_event, limit) => {
    return getPlayHistory(limit);
  });

  // Get listening stats
  ipcMain.handle('music:stats', () => {
    return getListeningStats();
  });

  // Get setting
  ipcMain.handle('music:get-setting', (_event, key) => {
    return getSetting(key);
  });

  // Set setting
  ipcMain.handle('music:set-setting', (_event, { key, value }) => {
    setSetting(key, value);
    return { success: true };
  });

  // Check if library is set up
  ipcMain.handle('music:is-setup', () => {
    const libDir = getSetting('library_dir');
    return { setup: !!libDir, libraryDir: libDir };
  });

  // Select library directory (for settings page)
  ipcMain.handle('music:select-library-dir', async () => {
    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openDirectory', 'createDirectory'],
      title: 'Select Library Directory',
    });
    if (result.canceled || result.filePaths.length === 0) {
      return { canceled: true };
    }
    return { canceled: false, path: result.filePaths[0] };
  });

  // Reset database
  ipcMain.handle('music:reset-database', () => {
    resetDatabase();
    return { success: true };
  });

  // Read cover art as base64
  ipcMain.handle('music:get-cover', (_event, coverPath) => {
    try {
      if (coverPath && fs.existsSync(coverPath)) {
        const data = fs.readFileSync(coverPath);
        const ext = path.extname(coverPath).toLowerCase();
        const mime = ext === '.png' ? 'image/png' :
                     ext === '.webp' ? 'image/webp' : 'image/jpeg';
        return `data:${mime};base64,${data.toString('base64')}`;
      }
    } catch {}
    return null;
  });

  // Get total tracks duration
  ipcMain.handle('music:total-duration', () => {
    const db = require('./database').getDatabase();
    const result = db.prepare('SELECT COALESCE(SUM(duration), 0) as total FROM tracks').get();
    return result.total;
  });

  // Playlist operations
  ipcMain.handle('playlist:create', (_event, { name, description }) => {
    return createPlaylist(name, description);
  });

  ipcMain.handle('playlist:get-all', () => {
    return getAllPlaylists();
  });

  ipcMain.handle('playlist:add-track', (_event, { playlistId, trackId }) => {
    return addTrackToPlaylist(playlistId, trackId);
  });

  ipcMain.handle('playlist:get-tracks', (_event, playlistId) => {
    return getPlaylistTracks(playlistId);
  });

  ipcMain.handle('playlist:remove-track', (_event, { playlistId, trackId }) => {
    return removeTrackFromPlaylist(playlistId, trackId);
  });

  ipcMain.handle('playlist:delete', (_event, playlistId) => {
    return deletePlaylist(playlistId);
  });

  ipcMain.handle('playlist:rename', (_event, { id, name }) => {
    return renamePlaylist(id, name);
  });

  ipcMain.handle('playlist:add-tracks', (_event, { playlistId, trackIds }) => {
    return addTracksToPlaylist(playlistId, trackIds);
  });

  ipcMain.handle('playlist:set-tracks', (_event, { playlistId, trackIds }) => {
    return setPlaylistTracks(playlistId, trackIds);
  });

  // ── LRC (Lyrics) operations ──

  // Set LRC path for a track
  ipcMain.handle('music:set-lrc', (_event, { trackId, lrcPath }) => {
    return setTrackLrc(trackId, lrcPath);
  });

  // Get LRC content for a track
  ipcMain.handle('music:get-lrc', (_event, trackId) => {
    const lrcPath = getTrackLrc(trackId);
    if (!lrcPath) return null;
    try {
      if (fs.existsSync(lrcPath)) {
        const content = fs.readFileSync(lrcPath, 'utf-8');
        return { content, path: lrcPath };
      }
    } catch (err) {
      console.error('Failed to read LRC file:', err.message);
    }
    return null;
  });

  // Upload LRC file for a track
  ipcMain.handle('music:upload-lrc', async (_event, trackId) => {
    const track = getTrackById(trackId);
    if (!track) return { error: 'Track not found' };

    const result = await dialog.showOpenDialog(mainWindow, {
      properties: ['openFile'],
      title: 'Select LRC Lyrics File',
      filters: [{ name: 'LRC Lyrics', extensions: ['lrc'] }, { name: 'All Files', extensions: ['*'] }],
    });

    if (result.canceled || result.filePaths.length === 0) {
      return { canceled: true };
    }

    const sourcePath = result.filePaths[0];
    const lrcFileName = path.basename(sourcePath);

    // Copy to the same directory as the audio file
    const audioDir = path.dirname(track.file_path);
    const targetPath = path.join(audioDir, lrcFileName);

    try {
      // Only copy if different path
      if (sourcePath !== targetPath) {
        fs.copyFileSync(sourcePath, targetPath);
      }
      setTrackLrc(trackId, targetPath);
      return { success: true, lrcPath: targetPath };
    } catch (err) {
      console.error('Failed to copy LRC file:', err.message);
      return { error: err.message };
    }
  });

  // Remove LRC file from a track
  ipcMain.handle('music:remove-lrc', (_event, trackId) => {
    const track = getTrackById(trackId);
    if (!track) return { error: 'Track not found' };

    const lrcPath = getTrackLrc(trackId);
    if (lrcPath && fs.existsSync(lrcPath)) {
      try {
        fs.unlinkSync(lrcPath);
      } catch (err) {
        console.error('Failed to delete LRC file:', err.message);
      }
    }

    clearTrackLrc(trackId);
    return { success: true };
  });
}

// ── App lifecycle ──

app.whenReady().then(() => {
  try {
    initDatabase();
  } catch (err) {
    console.error('Database init failed:', err.message);
    dialog.showErrorBox('Database Error', `Failed to initialize database:\n${err.message}`);
    app.quit();
    return;
  }
  registerProtocol();
  setupIPC();
  createWindow();

  // Register media keys
  globalShortcut.register('MediaPlayPause', () => {
    mainWindow?.webContents.send('media-key', 'playpause');
  });
  globalShortcut.register('MediaNextTrack', () => {
    mainWindow?.webContents.send('media-key', 'next');
  });
  globalShortcut.register('MediaPreviousTrack', () => {
    mainWindow?.webContents.send('media-key', 'previous');
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  globalShortcut.unregisterAll();
  closeDatabase();
  if (process.platform !== 'darwin') app.quit();
});
