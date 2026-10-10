import ReactDOM from 'react-dom/client';
import App from './App';
import EqWindow from './components/EqWindow';
import ErrorBoundary from './components/ErrorBoundary';
import OnboardingPage from './components/OnboardingPage';
import { PlayerProvider } from './context/PlayerContext';
import './styles/index.css';

const root = ReactDOM.createRoot(document.getElementById('root'));
const view = new URLSearchParams(window.location.search).get('view');

if (view === 'eq') {
  root.render(<ErrorBoundary><EqWindow /></ErrorBoundary>);
} else if (view === 'onboarding') {
  root.render(<ErrorBoundary><OnboardingPage onDone={() => window.freeplayer.finishOnboarding()} /></ErrorBoundary>);
} else {
  root.render(
    <ErrorBoundary>
      <PlayerProvider>
        <App />
      </PlayerProvider>
    </ErrorBoundary>
  );
}
