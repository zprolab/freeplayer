import { describe, it, expect } from 'vitest';
import { reducer, initialState } from '../src/context/PlayerContext';

function baseState(overrides = {}) {
  return {
    tracks: [],
    currentTrack: null,
    queue: [],
    queueIndex: -1,
    shuffledQueue: [],
    playlistTracks: [],
    playlists: [],
    activePlaylistId: null,
    isPlaying: false,
    ...overrides,
  };
}

describe('PlayerContext reducer', () => {
  it('SET_TRACK_FIELDS merges fields into the matching track everywhere', () => {
    const trackA = { id: 1, title: 'A', cover_path: null };
    const trackB = { id: 2, title: 'B', cover_path: null };
    const state = baseState({
      currentTrack: trackA,
      tracks: [{ ...trackA }, { ...trackB }],
      queue: [{ ...trackB }],
      playlistTracks: [{ ...trackA }],
    });

    const next = reducer(state, { type: 'SET_TRACK_FIELDS', payload: { id: 1, fields: { cover_path: '/covers/1.jpg' } } });

    expect(next.currentTrack).toEqual({ id: 1, title: 'A', cover_path: '/covers/1.jpg' });
    expect(next.tracks[0].cover_path).toBe('/covers/1.jpg');
    expect(next.playlistTracks[0].cover_path).toBe('/covers/1.jpg');
    // Track B untouched everywhere
    expect(next.tracks[1].cover_path).toBeNull();
    expect(next.queue[0].cover_path).toBeNull();
    // Other state preserved
    expect(next.queueIndex).toBe(-1);
    expect(next.isPlaying).toBe(false);
  });

  it('SET_TRACK_FIELDS does not clobber a different current track', () => {
    const state = baseState({
      currentTrack: { id: 2, title: 'B', cover_path: null },
      tracks: [{ id: 1, title: 'A', cover_path: null }],
    });

    const next = reducer(state, { type: 'SET_TRACK_FIELDS', payload: { id: 1, fields: { cover_path: '/covers/1.jpg' } } });

    expect(next.currentTrack).toEqual({ id: 2, title: 'B', cover_path: null });
    expect(next.tracks[0].cover_path).toBe('/covers/1.jpg');
  });

  it('SET_TRACK_FIELDS is a no-op without an id or fields', () => {
    const state = baseState({ currentTrack: { id: 1 } });
    expect(reducer(state, { type: 'SET_TRACK_FIELDS', payload: {} })).toBe(state);
    expect(reducer(state, { type: 'SET_TRACK_FIELDS', payload: null })).toBe(state);
  });

  it('initialState has sidebarCollapsed defaulting to false', () => {
    expect(initialState.sidebarCollapsed).toBe(false);
  });

  it('SET merges sidebarCollapsed into state', () => {
    const next = reducer(initialState, { type: 'SET', payload: { sidebarCollapsed: true } });
    expect(next.sidebarCollapsed).toBe(true);
  });

  it('existing actions keep working', () => {
    let state = baseState();
    state = reducer(state, { type: 'SET', payload: { isPlaying: true } });
    expect(state.isPlaying).toBe(true);
    state = reducer(state, { type: 'SET_PLAYLISTS', payload: [{ id: 5 }] });
    expect(state.playlists).toEqual([{ id: 5 }]);
    state = reducer(state, { type: 'SELECT_PLAYLIST', payload: 5 });
    expect(state.activePlaylistId).toBe(5);
    expect(state.playlistTracks).toEqual([]);
    state = reducer(state, { type: 'SET_CURRENT_TRACK', payload: { id: 1 } });
    expect(state.currentTrack).toEqual({ id: 1 });
    expect(reducer(state, { type: 'UNKNOWN', payload: {} })).toBe(state);
  });
});
