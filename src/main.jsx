import ReactDOM from 'react-dom/client';
import App from '@/App.jsx';
import EqWindow from '@/features/playback/ui/EqWindow.jsx';
import ErrorBoundary from '@/app/ErrorBoundary.jsx';
import OnboardingPage from '@/features/onboarding/ui/OnboardingPage.jsx';
import { PlayerProvider } from '@/app/PlayerProvider.jsx';
import './styles/index.css';
import * as client from '@/core/client.js';

const root = ReactDOM.createRoot(document.getElementById('root'));
const view = new URLSearchParams(window.location.search).get('view');

if (view === 'eq') {
  root.render(<ErrorBoundary><EqWindow /></ErrorBoundary>);
} else if (view === 'onboarding') {
  root.render(<ErrorBoundary><OnboardingPage onDone={() => client.shell.finishOnboarding()} /></ErrorBoundary>);
} else {
  root.render(
    <ErrorBoundary>
      <PlayerProvider>
        <App />
      </PlayerProvider>
    </ErrorBoundary>
  );
}
