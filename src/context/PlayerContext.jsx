import React, { createContext, useContext, useReducer, useRef } from 'react';

const PlayerContext = createContext(null);

const VIEWS = {
  LIBRARY: 'library',
  NOW_PLAYING: 'now-playing',
  STATS: 'stats',
  SETTINGS: 'settings',
};

const initialState = {
  view: VIEWS.LIBRARY,
  tracks: [],
  currentTrack: null,
  isPlaying: false,
  queue: [],
  queueIndex: -1,
  shuffledQueue: [],
  currentTime: 0,
  duration: 0,
  volume: 0.8,
  isLoading: true,
  isSetup: false,
  libraryDir: '',
  searchQuery: '',
  sortBy: 'imported_at',
  sortDir: 'DESC',
  visualizerMode: 'waveform',
  importMode: 'copy',
  importModalOpen: false,
  defaultVolume: 0.8,
  defaultVisualizer: 'waveform',
  playMode: 'sequential',
  playlists: [],
  activePlaylistId: null,
  playlistTracks: [],
  playlistModal: null,
  pendingAddTrack: null,
  dragOver: false,
  initialPaths: null,
};

function reducer(state, action) {
  switch (action.type) {
    case 'SET': return { ...state, ...action.payload };
    case 'SET_TRACKS': return { ...state, tracks: action.payload };
    case 'SET_CURRENT_TRACK': return { ...state, currentTrack: action.payload };
    case 'SET_IS_PLAYING': return { ...state, isPlaying: action.payload };
    case 'SET_QUEUE': return { ...state, queue: action.payload };
    case 'SET_QUEUE_INDEX': return { ...state, queueIndex: action.payload };
    case 'SET_SHUFFLED_QUEUE': return { ...state, shuffledQueue: action.payload };
    case 'SET_VOLUME': return { ...state, volume: action.payload };
    case 'SET_PLAY_MODE': return { ...state, playMode: action.payload, shuffledQueue: action.payload === 'shuffle' ? state.shuffledQueue : [] };
    case 'SET_PLAYLISTS': return { ...state, playlists: action.payload || [] };
    case 'SELECT_PLAYLIST': return { ...state, activePlaylistId: action.payload, playlistTracks: [], view: VIEWS.LIBRARY };
    case 'SET_PLAYLIST_TRACKS': return { ...state, playlistTracks: action.payload || [] };
    default: return state;
  }
}

export function PlayerProvider({ children }) {
  const [state, dispatch] = useReducer(reducer, initialState);
  const audioRef = useRef(new Audio());
  const playSessionIdRef = useRef(null);
  const playStartTimeRef = useRef(null);

  const value = { state, dispatch, audioRef, playSessionIdRef, playStartTimeRef };
  return (
    <PlayerContext.Provider value={value}>
      {children}
    </PlayerContext.Provider>
  );
}

export function usePlayer() {
  const ctx = useContext(PlayerContext);
  if (!ctx) throw new Error('usePlayer must be used within PlayerProvider');
  return ctx;
}

export { VIEWS };
