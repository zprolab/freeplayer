import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import { PlayerProvider } from './context/PlayerContext';
import './App.css';

ReactDOM.createRoot(document.getElementById('root')).render(
  <PlayerProvider>
    <App />
  </PlayerProvider>
);
