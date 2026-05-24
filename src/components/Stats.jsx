import React, { useState, useEffect } from 'react';

function formatDuration(seconds) {
  if (!seconds || seconds === 0) return '0m';
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

function formatNumber(num) {
  if (!num) return '0';
  return num.toLocaleString();
}

export default function Stats() {
  const [stats, setStats] = useState(null);
  const [history, setHistory] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const [s, h] = await Promise.all([
        window.freeplayer.getStats(),
        window.freeplayer.getPlayHistory(30),
      ]);
      setStats(s);
      setHistory(h);
      setLoading(false);
    }
    load();
  }, []);

  if (loading) {
    return (
      <div className="stats-loading">
        <div className="loading-spinner" />
      </div>
    );
  }

  if (!stats) return null;

  return (
    <div className="stats">
      {/* Overview cards */}
      <div className="stats-cards">
        <div className="stat-card">
          <div className="stat-card-icon stat-card-icon--time">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
              <circle cx="12" cy="12" r="10"/>
              <polyline points="12 6 12 12 16 14"/>
            </svg>
          </div>
          <div className="stat-card-body">
            <span className="stat-card-value mono">{formatDuration(stats.totalTime)}</span>
            <span className="stat-card-label">Total Listening Time</span>
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-card-icon stat-card-icon--plays">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
              <polygon points="5 3 19 12 5 21 5 3" fill="currentColor"/>
            </svg>
          </div>
          <div className="stat-card-body">
            <span className="stat-card-value mono">{formatNumber(stats.totalPlays)}</span>
            <span className="stat-card-label">Total Plays</span>
          </div>
        </div>

        <div className="stat-card">
          <div className="stat-card-icon stat-card-icon--unique">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
              <path d="M9 18V5l12-2v13"/>
              <circle cx="6" cy="18" r="3"/>
              <circle cx="18" cy="16" r="3"/>
            </svg>
          </div>
          <div className="stat-card-body">
            <span className="stat-card-value mono">{formatNumber(stats.uniqueTracksPlayed)}</span>
            <span className="stat-card-label">Unique Tracks</span>
          </div>
        </div>
      </div>

      <div className="stats-grid">
        {/* Top tracks */}
        <div className="stats-panel">
          <h3 className="panel-title">Most Played Tracks</h3>
          {stats.topTracks.length === 0 ? (
            <p className="panel-empty">No play data yet.</p>
          ) : (
            <table className="data-table data-table--compact">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Title</th>
                  <th>Artist</th>
                  <th className="right">Plays</th>
                  <th className="right">Time</th>
                </tr>
              </thead>
              <tbody>
                {stats.topTracks.map((track, idx) => (
                  <tr key={track.id}>
                    <td className="mono cell-index">{idx + 1}</td>
                    <td className="cell-title">{track.title}</td>
                    <td className="cell-artist">{track.artist}</td>
                    <td className="mono right">{formatNumber(track.play_count)}</td>
                    <td className="mono right">{formatDuration(track.total_listen_time)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>

        {/* Top artists */}
        <div className="stats-panel">
          <h3 className="panel-title">Top Artists</h3>
          {stats.topArtists.length === 0 ? (
            <p className="panel-empty">No play data yet.</p>
          ) : (
            <table className="data-table data-table--compact">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Artist</th>
                  <th className="right">Plays</th>
                  <th className="right">Time</th>
                </tr>
              </thead>
              <tbody>
                {stats.topArtists.map((artist, idx) => (
                  <tr key={artist.artist}>
                    <td className="mono cell-index">{idx + 1}</td>
                    <td>{artist.artist}</td>
                    <td className="mono right">{formatNumber(artist.play_count)}</td>
                    <td className="mono right">{formatDuration(artist.total_listen_time)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>

      {/* Daily listening chart */}
      {stats.dailyStats.length > 0 && (
        <div className="stats-panel stats-panel--full">
          <h3 className="panel-title">Listening History (30 days)</h3>
          <div className="daily-chart">
            {stats.dailyStats.slice(0, 14).reverse().map((day) => {
              const maxTime = Math.max(...stats.dailyStats.map(d => d.total_time), 1);
              const barHeight = (day.total_time / maxTime) * 100;
              return (
                <div key={day.date} className="chart-bar-group">
                  <div className="chart-bar-wrapper">
                    <div
                      className="chart-bar"
                      style={{ height: `${Math.max(barHeight, 2)}%` }}
                      title={`${formatDuration(day.total_time)} - ${day.plays} plays`}
                    />
                  </div>
                  <span className="chart-label mono">
                    {new Date(day.date + 'T00:00:00').toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Recent history */}
      <div className="stats-panel stats-panel--full">
        <h3 className="panel-title">Recent Plays</h3>
        {history.length === 0 ? (
          <p className="panel-empty">No play history yet.</p>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>Title</th>
                <th>Artist</th>
                <th>Started</th>
                <th className="right">Duration</th>
                <th className="right">%</th>
              </tr>
            </thead>
            <tbody>
              {history.map((entry) => (
                <tr key={entry.id}>
                  <td className="cell-title">{entry.title}</td>
                  <td className="cell-artist">{entry.artist}</td>
                  <td className="mono">
                    {new Date(entry.started_at + 'Z').toLocaleString(undefined, {
                      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
                    })}
                  </td>
                  <td className="mono right">{formatDuration(entry.duration_seconds)}</td>
                  <td className="mono right">{entry.play_percentage}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
