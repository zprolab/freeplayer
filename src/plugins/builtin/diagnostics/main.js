let lastPlayback = 0;

function safe(value) {
  try { return JSON.stringify(value); } catch { return String(value); }
}

export function activate(api) {
  const write = (level, message) => api.log(level, message);
  return {
    onTrackChanged(track) {
      write('info', `Track changed: ${safe({ id: track?.id, title: track?.title, artist: track?.artist, file: track?.file_path })}`);
    },
    onPlaybackChanged(state) {
      const now = Date.now();
      if (now - lastPlayback < 1000 && state?.isPlaying) return;
      lastPlayback = now;
      write('info', `Playback state: ${safe({ isPlaying: !!state?.isPlaying, currentTime: state?.currentTime, duration: state?.duration })}`);
    },
  };
}
