import ReactDOM from 'react-dom/client';
import App from './App';
import EqWindow from './components/EqWindow';
import OnboardingPage from './components/OnboardingPage';
import { PlayerProvider } from './context/PlayerContext';
import './App.css';

const root = ReactDOM.createRoot(document.getElementById('root'));
const view = new URLSearchParams(window.location.search).get('view');

if (view === 'eq') {
  root.render(<EqWindow />);
} else if (view === 'onboarding') {
  root.render(<OnboardingPage onDone={() => window.freeplayer.finishOnboarding()} />);
} else {
  root.render(
    <PlayerProvider>
      <App />
    </PlayerProvider>
  );
}
