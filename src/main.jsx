import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import EqWindow from './components/EqWindow';
import { PlayerProvider } from './context/PlayerContext';
import './App.css';

const root = ReactDOM.createRoot(document.getElementById('root'));
const isEqView = new URLSearchParams(window.location.search).get('view') === 'eq';

if (isEqView) {
  root.render(<EqWindow />);
} else {
  root.render(
    <PlayerProvider>
      <App />
    </PlayerProvider>
  );
}
