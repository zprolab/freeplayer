import { useCallback, useEffect, useRef } from 'react';
import { usePlayer } from '../context/PlayerContext';
import { computeNextIndex, computePrevIndex, buildShuffleOrder } from './playQueue';
import { getPlaybackEngine } from '../player/playbackEngine';
import * as client from '../core/client';

// React adapter over PlaybackEngine.
//
// The hook keeps only what is genuinely UI-layer: translating React state
// (queue, play mode) into engine calls, and dispatching engine events back into
// the player reducer. The audio element, the Web Audio graph, the media events
// and all session/listening accounting live in src/player/playbackEngine.js and
// no longer depend on React — see that file for the reasoning.
export function usePlayback() {
  const { state, dispatch, audioRef } = usePlayer();
  const engine = getPlaybackEngine();

  // The player provider owns the <audio> element; hand it to the engine once.
  // In production both are process-lifetime singletons.
  engine.audio = audioRef.current;
  engine.bridge = typeof window !== 'undefined' ? window.freeplayer : engine.bridge;

  // Serialises session transitions: every playTrack queues behind the one
  // before it, so rapid calls each end the session the previous one left.
  const sessionTransitionRef = useRef(Promise.resolve());

  const playTrack = useCallback(async (track) => {
    const transition = sessionTransitionRef.current
      .catch(() => {})
      .then(async () => {
        // Queue index is the caller's job (handleNext/handlePrev/
        // playTrackFromList already dispatch it) — doing it here from a stale
        // closure would overwrite the index the caller just set.
        try {
          await engine.play(track);
          // The engine owns the audio element; which track is "current" is UI
          // state, so it is published here. Dropping this in the UI/engine split
          // left currentTrack stale — the player bar and the library row kept
          // showing the previously selected track while audio had moved on.
          dispatch({ type: 'SET_CURRENT_TRACK', payload: track });
        } catch (err) {
          console.error('Playback failed:', err);
        }
      });
    sessionTransitionRef.current = transition;
    try {
      await transition;
    } catch (err) {
      console.error('Playback transition failed:', err);
    }
  }, [engine, dispatch]);

  const togglePlayPause = useCallback(() => {
    if (engine.paused) {
      if (!engine.audio?.src && state.tracks.length > 0) {
        // Starting from a stopped state: seed the queue as well, or Next/Prev
        // bail out and the newly playing track cannot be advanced. The index
        // must be reset with it — leaving whatever index the previous queue had
        // made Next/Prev skip to an unrelated position.
        dispatch({ type: 'SET_QUEUE', payload: state.tracks });
        dispatch({ type: 'SET_QUEUE_INDEX', payload: 0 });
      }
      engine.resume();
    } else {
      engine.pause();
    }
  }, [engine, state.tracks, dispatch]);

  const handleNext = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue, currentTrack } = state;
    if (!queue.length) return;

    if (playMode === 'repeat-one') {
      // Replays through the engine so the loop is reported as one play per
      // loop instead of a single session that never ends.
      if (currentTrack) playTrack(currentTrack);
      else engine.seek(0);
      return;
    }

    const { nextIdx } = computeNextIndex({ queue, queueIndex, playMode, shuffledQueue });
    if (nextIdx < 0) return; // queue no longer contains the target — skip
    const nextTrack = queue[nextIdx];
    if (!nextTrack) return; // index/queue out of sync — never play undefined
    dispatch({ type: 'SET_QUEUE_INDEX', payload: nextIdx });
    playTrack(nextTrack);
  }, [state, dispatch, engine, playTrack]);

  const handlePrev = useCallback(() => {
    const { queue, queueIndex, playMode, shuffledQueue } = state;
    if (!queue.length) return;

    const { prevIdx } = computePrevIndex({
      queue, queueIndex, currentTime: engine.currentTime, playMode, shuffledQueue,
    });
    if (prevIdx === queueIndex) {
      engine.seek(0);
      return;
    }
    if (prevIdx < 0) return;
    const prevTrack = queue[prevIdx];
    if (!prevTrack) return;
    dispatch({ type: 'SET_QUEUE_INDEX', payload: prevIdx });
    playTrack(prevTrack);
  }, [state, dispatch, engine, playTrack]);

  const handleSeek = useCallback((time) => {
    engine.seek(time);
    dispatch({ type: 'SET', payload: { currentTime: time } });
  }, [engine, dispatch]);

  const handleVolumeChange = useCallback((vol) => {
    // Reject junk input before it reaches the engine gain node or the DB
    // (NaN would persist String(NaN) and poison the graph gain).
    if (!Number.isFinite(vol)) return;
    const v = Math.min(Math.max(vol, 0), 1);
    engine.setVolume(v);
    dispatch({ type: 'SET_VOLUME', payload: v });
    client.settings.set('volume', String(v))
      .catch(() => {});
  }, [engine, dispatch]);

  const playTrackFromList = useCallback(async (track, trackList) => {
    dispatch({ type: 'SET_QUEUE', payload: trackList });
    const idx = trackList.findIndex(t => t.id === track.id);
    dispatch({ type: 'SET_QUEUE_INDEX', payload: idx });

    if (state.playMode === 'shuffle') {
      // Seed the order with the clicked track first and everything else once
      // behind it — see buildShuffleOrder.
      dispatch({ type: 'SET_SHUFFLED_QUEUE', payload: buildShuffleOrder(trackList, track.id) });
    }

    await playTrack(track);
  }, [dispatch, state.playMode, playTrack]);

  // Latest playback handlers behind a ref so the event subscription below
  // registers once — the handlers are rebuilt on every state change and
  // depending on them directly would re-subscribe every second during playback.
  const playHandlersRef = useRef({ togglePlayPause, handleNext, handlePrev });
  playHandlersRef.current = { togglePlayPause, handleNext, handlePrev };

  // Engine → reducer bridge.
  useEffect(() => {
    engine.bind();
    const unsubscribe = engine.subscribe((type, payload) => {
      switch (type) {
        case 'timeupdate':
          dispatch({ type: 'SET', payload: { currentTime: payload } });
          break;
        case 'durationchange':
          dispatch({ type: 'SET', payload: { duration: payload } });
          break;
        case 'playing':
          dispatch({ type: 'SET_IS_PLAYING', payload: payload });
          break;
        case 'ended':
          playHandlersRef.current.handleNext();
          break;
        case 'error':
          console.error('Audio error:', payload.name, payload.message || '', 'src:', payload.src);
          client.diagnostics.log('playback', 'error', `Audio error: ${JSON.stringify(payload)}`);
          break;
        case 'mediastate':
          client.diagnostics.log('playback', 'info', `Media event ${payload.type}: ${JSON.stringify(payload)}`);
          break;
        default:
          break;
      }
    });
    return unsubscribe;
  }, [engine, dispatch]);

  // Volume is applied by the engine (element volume + graph gain node).
  useEffect(() => {
    engine.setVolume(state.volume);
  }, [state.volume, engine]);

  // Unmount: report the open session, then let go of the listeners. The engine
  // itself survives a remount (StrictMode/HMR), so playback is not interrupted
  // and the audio graph is not torn down.
  useEffect(() => {
    return () => {
      (async () => {
        try {
          await sessionTransitionRef.current;
        } catch {}
        try {
          await engine.closeSessionOnUnmount();
        } catch (err) {
          console.error('Failed to end play session on unmount:', err);
        }
      })();
      engine.unbind();
    };
  }, [engine]);

  // Push playback state to the main process for the tray menu. The native side
  // only reads isPlaying, so re-sending on track change carries no information.
  useEffect(() => {
      // The client rejects when there is no bridge; this is fire-and-forget.
      client.playback.sendState(state.isPlaying).catch(() => {});
  }, [state.isPlaying]);

  // System media keys — one global handler, dispatching through the ref so the
  // latest handlers are used. Unmount re-registers a no-op rather than leaving a
  // stale handler dispatching into unmounted state.
  useEffect(() => {
    const handler = (action) => {
      const h = playHandlersRef.current;
      switch (action) {
        case 'playpause': h.togglePlayPause(); break;
        case 'next': h.handleNext(); break;
        case 'previous': h.handlePrev(); break;
      }
    };
    client.playback.onMediaKey(handler);
    return () => {
      client.playback.onMediaKey(() => {});
    };
  }, []);

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
