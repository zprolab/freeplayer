import { useCallback, useEffect } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { audioEngine } from '../audioEngine';

function shuffleArray(array) {
  const a = [...array];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export function usePlayback() {
  const { state, dispatch, audioRef, playSessionIdRef, playStartTimeRef } = usePlayer();

  const startPlaySession = useCallback(async (trackId) => {
    const prevSid = playSessionIdRef.current;
    if (prevSid && playStartTimeRef.current) {
      const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
      const trackDuration = audioRef.current.duration || 0;
      const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
      await window.freeplayer.playEnd({
        sessionId: prevSid,
        durationSeconds: Math.round(elapsed),
        playPercentage: Math.round(percentage),
      });
    }
    const sessionId = await window.freeplayer.playStart(trackId);
    playSessionIdRef.current = sessionId;
    playStartTimeRef.current = Date.now();
  }, [audioRef, playSessionIdRef, playStartTimeRef]);

  const playTrack = useCallback(async (track) => {
    dispatch({ type: 'SET_CURRENT_TRACK', payload: track });
    audioRef.current.src = `media://${track.file_path}`;
    const gainDb = track.replaygain_gain || 0;
    audioEngine.setGain(gainDb);
    try {
      await audioRef.current.play();
      await startPlaySession(track.id);
    } catch (err) {
      console.error('Playback failed:', err);
    }
  }, [dispatch, audioRef, startPlaySession]);

  const togglePlayPause = useCallback(() => {
    const audio = audioRef.current;
    if (!audio.src && state.tracks.length > 0) {
      playTrack(state.tracks[0]);
      return;
    }
    if (audio.paused) {
      audio.play().catch(console.error);
    } else {
      audio.pause();
    }
  }, [audioRef, state.tracks, playTrack]);

  const handleNext = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
    if (!queue.length) return;

    if (playMode === 'repeat-one') {
      audioRef.current.currentTime = 0;
      audioRef.current.play().catch(console.error);
      return;
    }

    let nextIdx;
    if (playMode === 'shuffle') {
      const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
      const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
      if (currentShuffledIdx < shuffled.length - 1) {
        nextIdx = queue.findIndex(t => t.id === shuffled[currentShuffledIdx + 1].id);
      } else {
        const reshuffled = shuffleArray(queue);
        dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: reshuffled });
        nextIdx = queue.findIndex(t => t.id === reshuffled[0].id);
      }
    } else {
      nextIdx = queueIndex < queue.length - 1 ? queueIndex + 1 : 0;
    }

    dispatch({ type: 'SET_QUEUE_INDEX', payload: nextIdx });
    playTrack(queue[nextIdx]);
  }, [state, audioRef, dispatch, playTrack]);

  const handlePrev = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
    if (!queue.length) return;

    if (audioRef.current.currentTime > 3) {
      audioRef.current.currentTime = 0;
      return;
    }

    let prevIdx;
    if (playMode === 'shuffle') {
      const shuffled = shuffledQueue.length > 0 ? shuffledQueue : queue;
      const currentShuffledIdx = shuffled.findIndex(t => t.id === queue[queueIndex]?.id);
      if (currentShuffledIdx > 0) {
        prevIdx = queue.findIndex(t => t.id === shuffled[currentShuffledIdx - 1].id);
      } else {
        prevIdx = queue.findIndex(t => t.id === shuffled[shuffled.length - 1].id);
      }
    } else {
      prevIdx = queueIndex > 0 ? queueIndex - 1 : queue.length - 1;
    }

    dispatch({ type: 'SET_QUEUE_INDEX', payload: prevIdx });
    playTrack(queue[prevIdx]);
  }, [state, audioRef, dispatch, playTrack]);

  const handleSeek = useCallback((time) => {
    audioRef.current.currentTime = time;
    dispatch({ type: 'SET', payload: { currentTime: time } });
  }, [audioRef, dispatch]);

  const handleVolumeChange = useCallback((vol) => {
    audioRef.current.volume = vol;
    dispatch({ type: 'SET_VOLUME', payload: vol });
  }, [audioRef, dispatch]);

  const playTrackFromList = useCallback(async (track, trackList) => {
    dispatch({ type: 'SET_QUEUE', payload: trackList });
    const idx = trackList.findIndex(t => t.id === track.id);
    dispatch({ type: 'SET_QUEUE_INDEX', payload: idx });

    if (state.playMode === 'shuffle') {
      const shuffled = shuffleArray(trackList);
      const clickedIdx = shuffled.findIndex(t => t.id === track.id);
      if (clickedIdx > 0) {
        [shuffled[0], shuffled[clickedIdx]] = [shuffled[clickedIdx], shuffled[0]];
      }
      dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: shuffled });
    }

    await playTrack(track);
  }, [dispatch, state.playMode, playTrack]);

  // Audio element event listeners (no longer tied to volume changes)
  useEffect(() => {
    const audio = audioRef.current;

    const onTimeUpdate = () => dispatch({ type: 'SET', payload: { currentTime: audio.currentTime } });
    const onDurationChange = () => dispatch({ type: 'SET', payload: { duration: audio.duration || 0 } });
    const onEnded = () => handleNext();
    const onPlay = () => dispatch({ type: 'SET_IS_PLAYING', payload: true });
    const onPause = () => dispatch({ type: 'SET_IS_PLAYING', payload: false });
    const onError = () => {
      const err = audio.error;
      const codes = { 1: 'MEDIA_ERR_ABORTED', 2: 'MEDIA_ERR_NETWORK', 3: 'MEDIA_ERR_DECODE', 4: 'MEDIA_ERR_SRC_NOT_SUPPORTED' };
      console.error('Audio error:', codes[err?.code] || 'UNKNOWN', err?.message || '', 'src:', audio.src);
    };

    audio.addEventListener('timeupdate', onTimeUpdate);
    audio.addEventListener('durationchange', onDurationChange);
    audio.addEventListener('ended', onEnded);
    audio.addEventListener('play', onPlay);
    audio.addEventListener('pause', onPause);
    audio.addEventListener('error', onError);

    return () => {
      audio.removeEventListener('timeupdate', onTimeUpdate);
      audio.removeEventListener('durationchange', onDurationChange);
      audio.removeEventListener('ended', onEnded);
      audio.removeEventListener('play', onPlay);
      audio.removeEventListener('pause', onPause);
      audio.removeEventListener('error', onError);
    };
  }, [audioRef, dispatch, handleNext]);

  // Separate volume effect — no longer tears down event listeners
  useEffect(() => {
    audioRef.current.volume = state.volume;
  }, [state.volume, audioRef]);

  // End play session on unmount
  useEffect(() => {
    return () => {
      const sid = playSessionIdRef.current;
      if (sid && playStartTimeRef.current) {
        const elapsed = (Date.now() - playStartTimeRef.current) / 1000;
        const trackDuration = audioRef.current.duration || 0;
        const percentage = trackDuration > 0 ? Math.min((elapsed / trackDuration) * 100, 100) : 0;
        window.freeplayer.playEnd({
          sessionId: sid,
          durationSeconds: Math.round(elapsed),
          playPercentage: Math.round(percentage),
        });
      }
      audioEngine.dispose();
    };
  }, [audioRef, playSessionIdRef, playStartTimeRef]);

  // System media key support
  useEffect(() => {
    if (!window.freeplayer.onMediaKey) return;
    const handler = (action) => {
      switch (action) {
        case 'playpause': togglePlayPause(); break;
        case 'next': handleNext(); break;
        case 'previous': handlePrev(); break;
      }
    };
    window.freeplayer.onMediaKey(handler);
  }, [togglePlayPause, handleNext, handlePrev]);

  return {
    playTrack,
    togglePlayPause,
    handleNext,
    handlePrev,
    handleSeek,
    handleVolumeChange,
    playTrackFromList,
  };
}
