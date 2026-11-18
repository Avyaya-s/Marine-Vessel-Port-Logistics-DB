// Small reusable pieces shared by the pages.
import { riskLevel } from './charts.jsx'

// Port call statuses use the chart colours; customs statuses use the
// status (severity) colours.  The word is always shown, never colour alone.
const BADGE_CLASS = {
  'Expected': 's-expected', 'Waiting': 's-waiting', 'Berthed': 's-berthed', 'Departed': 's-departed',
  'Filed': 'sev-neutral', 'Under Review': 'sev-warning', 'Held': 'sev-critical', 'Cleared': 'sev-good',
}

export function StatusBadge({ status }) {
  return (
    <span className="badge">
      <span className={`badge-dot ${BADGE_CLASS[status] ?? 'sev-neutral'}`} aria-hidden="true" />
      {status}
    </span>
  )
}

export function RiskBadge({ score }) {
  const lvl = riskLevel(score)
  if (!lvl) return <span className="muted nowrap">not scored</span>
  return (
    <span className="risk nowrap">
      <span className={`sev-icon sev-${lvl.key}`} aria-hidden="true">{lvl.icon}</span>
      {score.toFixed(2)} <span className="muted small">{lvl.word}</span>
    </span>
  )
}

// Success or error banner after a button press.
export function Notice({ notice, onClose }) {
  if (!notice) return null
  return (
    <div className={`notice notice-${notice.kind}`} role="status">
      <span className="notice-icon" aria-hidden="true">{notice.kind === 'ok' ? '✓' : '!'}</span>
      <div className="notice-body">
        <strong>{notice.title}</strong>
        <p>{notice.text}</p>
      </div>
      <button className="notice-close" onClick={onClose} aria-label="Dismiss">×</button>
    </div>
  )
}

// Wraps a page section: shows loading / error states consistently.
export function Section({ title, subtitle, loading, error, children, actions }) {
  return (
    <section className="card section">
      <div className="section-head">
        <div>
          <h2>{title}</h2>
          {subtitle && <p className="muted small">{subtitle}</p>}
        </div>
        {actions}
      </div>
      {error ? <p className="load-error">Could not load: {error}. Is the backend running?</p>
        : loading ? <p className="muted">Loading…</p>
        : children}
    </section>
  )
}
