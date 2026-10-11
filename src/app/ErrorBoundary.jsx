import { Component } from 'react';
import { Button } from '@/ui/components/index.js';
import * as client from '@/core/client.js';

// Last-resort guard around the app shell.
//
// React 18 unmounts the whole root when a render throws and nothing catches it,
// so a single malformed value (a plugin manifest field, a track with a null
// artist, a native payload of the wrong shape) left the user with a blank
// window and no way back. Individual call sites are still fixed defensively —
// this only bounds the blast radius of the ones we have not found yet.
export default class ErrorBoundary extends Component {
  constructor(props) {
    super(props);
    this.state = { error: null };
  }

  static getDerivedStateFromError(error) {
    return { error };
  }

  componentDidCatch(error, info) {
    console.error('Unhandled render error:', error, info?.componentStack || '');
    try {
      client.diagnostics.log('ui', 'error', `Render error: ${error?.message || error}`);
    } catch {
      // Logging must never be the thing that crashes the crash handler.
    }
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="app-error" role="alert">
        <h1>Something went wrong</h1>
        <p className="mono">{String(this.state.error?.message || this.state.error)}</p>
        <div className="app-error-actions">
          <Button variant="secondary" onClick={() => this.setState({ error: null })}>
            Try again
          </Button>
          <Button variant="primary" onClick={() => window.location.reload()}>
            Reload
          </Button>
        </div>
      </div>
    );
  }
}
