import { useState, useCallback } from 'react';
import licenseText from '../../LICENSE?raw';
import { canAdvance, nextStep, prevStep, ONBOARDING_STEPS } from '../onboardingSteps';

const STEP_LABELS = {
  welcome: 'Welcome', license: 'License', privacy: 'Privacy', library: 'Library',
};

export default function OnboardingPage({ onDone }) {
  const [step, setStep] = useState('welcome');
  const [licenseAgreed, setLicenseAgreed] = useState(false);
  const [libraryPath, setLibraryPath] = useState('');
  const [choosing, setChoosing] = useState(false);
  const [error, setError] = useState('');

  const handleChooseLibrary = useCallback(async () => {
    if (choosing) return;
    setChoosing(true);
    setError('');
    try {
      const res = await window.freeplayer.selectLibraryDir();
      if (res && !res.canceled && res.libraryDir) setLibraryPath(res.libraryDir);
    } catch (err) {
      setError(err.message || 'Failed to select directory');
    } finally {
      setChoosing(false);
    }
  }, [choosing]);

  const handleFinish = useCallback(() => {
    onDone?.();
  }, [onDone]);

  const state = { licenseAgreed, libraryPath };
  const stepIndex = ONBOARDING_STEPS.indexOf(step);

  return (
    <div className="onboarding">
      <div className="onboarding-steps">
        {ONBOARDING_STEPS.map((s) => (
          <div key={s} className={`ob-step${s === step ? ' ob-step--active' : ''}`}>
            <span className="ob-dot" />
            <span className="ob-label">{STEP_LABELS[s]}</span>
          </div>
        ))}
      </div>

      <div className="onboarding-content">
        {step === 'welcome' && (
          <>
            <div className="ob-welcome-logo">
              <svg width="40" height="40" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="11" stroke="var(--gl-orange)" strokeWidth="1.5"/>
                <circle cx="12" cy="12" r="4" fill="var(--gl-orange)"/>
                <path d="M12 1v8M12 15v8M1 12h8M15 12h8" stroke="var(--gl-orange)" strokeWidth="1" opacity="0.4"/>
              </svg>
            </div>
            <h1 className="ob-title">Welcome to FreePlayer</h1>
            <p className="ob-subtitle">Your music stays on your disk. No account, no tracking.</p>
            <div className="ob-features">
              <div className="ob-feature">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>
                <div><b>Local library</b><span>Import with your own folder structure</span></div>
              </div>
              <div className="ob-feature">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 3v18h18"/><path d="M7 15l4-6 4 3 5-7"/></svg>
                <div><b>Listening stats</b><span>Play history stays in a local database</span></div>
              </div>
              <div className="ob-feature">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M12 8v8M8 12h8"/></svg>
                <div><b>Extensible</b><span>Plugins for lyrics, covers and more</span></div>
              </div>
            </div>
          </>
        )}

        {step === 'license' && (
          <>
            <h1 className="ob-title">License</h1>
            <p className="ob-subtitle">FreePlayer is free software under the GNU GPL v3.</p>
            <div className="ob-license mono">{licenseText}</div>
            <label className="ob-agree">
              <input type="checkbox" checked={licenseAgreed} onChange={(e) => setLicenseAgreed(e.target.checked)} />
              <span>I have read and agree to the license</span>
            </label>
          </>
        )}

        {step === 'privacy' && (
          <>
            <h1 className="ob-title">Your privacy</h1>
            <p className="ob-subtitle">FreePlayer is designed to stay on your machine.</p>
            <div className="ob-feature">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
              <div><b>Fully offline by default</b><span>No account, no telemetry, no network access unless you opt in</span></div>
            </div>
            <div className="ob-feature">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10"/><path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>
              <div><b>Optional online metadata</b><span>When Auto-Fetch is on, playing a track missing lyrics or artwork sends its title, artist and album to LRCLIB (lyrics) and iTunes (artwork). You can turn this off anytime in Settings.</span></div>
            </div>
          </>
        )}

        {step === 'library' && (
          <>
            <h1 className="ob-title">Choose your library</h1>
            <p className="ob-subtitle">All imported music is stored here, organized by Artist / Album.</p>
            <div className="ob-library-box">
              {libraryPath ? (
                <>
                  <span className="ob-library-label">Library folder</span>
                  <span className="ob-library-path mono">{libraryPath}</span>
                </>
              ) : (
                <span className="ob-library-empty">No library folder selected yet</span>
              )}
            </div>
            {error && <p className="ob-error">{error}</p>}
            <button className="btn btn-secondary" onClick={handleChooseLibrary} disabled={choosing}>
              {choosing ? 'Choosing…' : libraryPath ? 'Change…' : 'Choose Folder…'}
            </button>
          </>
        )}
      </div>

      <div className="onboarding-footer">
        {stepIndex > 0 && (
          <button className="btn btn-secondary" onClick={() => setStep(prevStep(step))}>Back</button>
        )}
        {step === 'library' ? (
          <button className="btn btn-primary" disabled={!canAdvance(step, state)} onClick={handleFinish}>
            Finish
          </button>
        ) : (
          <button className="btn btn-primary" disabled={!canAdvance(step, state)} onClick={() => setStep(nextStep(step))}>
            Continue
          </button>
        )}
      </div>
    </div>
  );
}
