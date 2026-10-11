import { useState, useRef, useEffect, useCallback } from 'react';
import { Button, ModalShell } from '../ui/components';
import * as client from '../core/client';

export default function ImportModal({ onClose, onComplete, importMode }) {
  const [step, setStep] = useState('select-source');
  const [sourceDir, setSourceDir] = useState('');
  const [files, setFiles] = useState([]);
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const [errorDetails, setErrorDetails] = useState([]);
  const startedRef = useRef(false);

  const handleSelectSource = useCallback(async () => {
    try {
      const result = await client.library.importDialog();
      if (result.canceled) {
        onComplete({ canceled: true });
        return;
      }
      setSourceDir(result.sourceDir);
      setStep('scanning');
      const foundFiles = await client.library.scanDirectory(result.sourceDir);
      // Native returns { files, truncated, scannedCount } so the UI can warn on
      // truncation; older builds may return a bare array — accept both. Treating
      // the dict as an array here crashed the confirm screen (files.slice is not
      // a function) and blanked the whole app.
      setFiles(Array.isArray(foundFiles) ? foundFiles : (foundFiles?.files ?? []));
      client.diagnostics.log('import-ui', 'info', `Scan completed: ${JSON.stringify({ sourceDir: result.sourceDir, files: Array.isArray(foundFiles) ? foundFiles.length : foundFiles?.files?.length || 0, truncated: foundFiles?.truncated, scannedCount: foundFiles?.scannedCount })}`);
      setStep('confirm');
    } catch (err) {
      console.error('Import scan error:', err);
      setError(err.message || 'Failed to scan directory');
      setStep('error');
    }
  }, [onComplete]);

  const handleImport = async () => {
    setStep('importing');
    setError('');
    setErrorDetails([]);
    try {
      const res = await client.library.importFiles({ files });
      client.diagnostics.log('import-ui', 'info', `Import response: ${JSON.stringify(res)}`);
      setResult(res);
      if (res.error) {
        setError(res.error);
        setErrorDetails(res.errors || []);
        setStep('error');
      } else if (res.imported === 0 && res.errors.length > 0) {
        setError(`All ${res.errors.length} files failed to import`);
        setErrorDetails(res.errors);
        setStep('error');
      } else {
        setStep('done');
      }
    } catch (err) {
      console.error('Import error:', err);
      client.diagnostics.log('import-ui', 'error', `Import exception: ${err?.stack || err?.message || String(err)}`);
      setError(err.message || 'Import failed');
      setStep('error');
    }
  };

  // Auto-start — the native folder picker opens on mount
  useEffect(() => {
    if (!startedRef.current) {
      startedRef.current = true;
      handleSelectSource();
    }
  }, [handleSelectSource]);


  return (
    <ModalShell
      title="Import Music"
      onClose={onClose}
      // The wizard must not be dismissed while an import is running.
      canClose={step !== 'importing'}
      headerExtra={(
          <span className="import-mode-badge">
            {importMode === 'symlink' ? (
              <>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                  <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
                  <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
                </svg>
                Symlink Mode
              </>
            ) : (
              <>
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2"/>
                  <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>
                </svg>
                Copy Mode
              </>
            )}
          </span>
      )}
    >
        <div className="modal-body">
          {/* Step indicator */}
          <div className="import-steps">
            {['Select Source', 'Scan', 'Review', 'Import'].map((label, idx) => (
              <div key={label} className={`import-step ${idx <= ['select-source','scanning','confirm','importing','done'].indexOf(step) ? 'import-step--active' : ''}`}>
                <div className="step-dot" />
                <span className="step-label">{label}</span>
              </div>
            ))}
          </div>

          {/* Scanning state */}
          {(step === 'select-source' || step === 'scanning') && (
            <div className="import-state">
              {step === 'select-source' ? (
                <p className="import-info">Select a folder containing your music files...</p>
              ) : (
                <div className="scanning-indicator">
                  <div className="loading-spinner" />
                  <p>Scanning {sourceDir}...</p>
                  <p className="scan-hint mono">{files.length} files found</p>
                </div>
              )}
            </div>
          )}

          {/* Confirm */}
          {step === 'confirm' && (
            <div className="import-confirm">
              <div className="import-summary">
                <div className="summary-row">
                  <span className="summary-label">Source</span>
                  <span className="summary-value mono">{sourceDir}</span>
                </div>
                <div className="summary-row">
                  <span className="summary-label">Files found</span>
                  <span className="summary-value mono highlight">{files.length} audio files</span>
                </div>
              </div>
              <div className="file-preview">
                <h4 className="preview-title">Files to import</h4>
                <div className="file-list">
                  {files.slice(0, 20).map((f, i) => (
                    <div key={i} className="file-item mono">
                      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
                        <path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>
                      </svg>
                      {f.replace(sourceDir, '')}
                    </div>
                  ))}
                  {files.length > 20 && (
                    <p className="more-files">+ {files.length - 20} more files</p>
                  )}
                </div>
              </div>
            </div>
          )}

          {/* Importing */}
          {step === 'importing' && (
            <div className="import-state">
              <div className="loading-spinner" />
              <p>Importing tracks... This may take a moment.</p>
            </div>
          )}

          {/* Done */}
          {step === 'done' && result && (
            <div className="import-done">
              <div className="done-icon">
                <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="var(--fp-success)" strokeWidth="1.8" strokeLinecap="round">
                  <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/>
                  <polyline points="22 4 12 14.01 9 11.01"/>
                </svg>
              </div>
              <h3>Import Complete</h3>
              <div className="import-results">
                <div className="result-item">
                  <span className="result-value" style={{ color: 'var(--fp-success)' }}>{result.imported}</span>
                  <span className="result-label">imported</span>
                </div>
                {result.errors.length > 0 && (
                  <div className="result-item">
                    <span className="result-value" style={{ color: 'var(--fp-accent)' }}>{result.errors.length}</span>
                    <span className="result-label">failed</span>
                  </div>
                )}
              </div>
            </div>
          )}

          {/* Error state */}
          {step === 'error' && (
            <div className="import-error-state">
              <div className="error-icon">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="var(--fp-danger)" strokeWidth="1.8" strokeLinecap="round">
                  <circle cx="12" cy="12" r="10"/>
                  <line x1="15" y1="9" x2="9" y2="15"/>
                  <line x1="9" y1="9" x2="15" y2="15"/>
                </svg>
              </div>
              <h3>Import Failed</h3>
              <p className="error-message">{error}</p>
              {errorDetails.length > 0 && (
                <div className="error-details">
                  {errorDetails.slice(0, 10).map((e, i) => (
                    <div key={i} className="error-detail-item mono">
                      <span className="error-file">{e.file.split('/').pop()}</span>
                      <span className="error-reason">{e.error}</span>
                    </div>
                  ))}
                  {errorDetails.length > 10 && (
                    <p className="more-errors">+ {errorDetails.length - 10} more errors</p>
                  )}
                </div>
              )}
            </div>
          )}
        </div>

        <div className="modal-footer">
          {step === 'confirm' && (
            <>
              <Button variant="secondary" onClick={() => {
                // Reopen the picker directly: resetting to 'select-source' left
                // the modal on a step whose only content is "Select a folder…"
                // with no button that could open one (the auto-start effect is
                // one-shot), a dead end.
                setFiles([]);
                handleSelectSource();
              }}>Back</Button>
              <Button variant="secondary" onClick={onClose}>Cancel</Button>
              <Button variant="primary" onClick={handleImport}>
                Import {files.length} Files
              </Button>
            </>
          )}
          {step === 'done' && (
            <Button variant="primary" onClick={() => onComplete({ canceled: false })}>
              View Library
            </Button>
          )}
          {step === 'error' && (
            <>
              <Button variant="secondary" onClick={onClose}>Close</Button>
              <Button variant="primary" onClick={handleSelectSource}>
                Try Again
              </Button>
            </>
          )}
        </div>
    </ModalShell>
  );
}
