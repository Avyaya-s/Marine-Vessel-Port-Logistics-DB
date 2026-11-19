import { useState } from 'react'
import { ROLE_LABEL, useAuth } from '../auth.jsx'

// Demo accounts (created by backend/manage_users.py demo).  Development only:
// a real deployment would not list accounts on the login page.
const DEMO = [
  ['admin', 'admin123', 'admin'],
  ['ops', 'ops123', 'operations'],
  ['customs', 'customs123', 'customs'],
  ['seaways', 'agent123', 'agent'],
  ['bluewater', 'agent123', 'agent'],
]

export default function Login() {
  const { login } = useAuth()
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState(null)
  const [busy, setBusy] = useState(false)

  async function submit(e) {
    e.preventDefault()
    setBusy(true); setError(null)
    try {
      await login(username.trim(), password)
    } catch (err) {
      setError(err.message)
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-page">
      <div className="login-card card">
        <div className="login-brand">
          <span className="brand-mark">⚓</span>
          <div>
            <div className="login-title">Port Logistics</div>
            <div className="muted small">Vessel traffic &amp; customs</div>
          </div>
        </div>

        <form onSubmit={submit} className="login-form">
          <label className="field"><span>Username</span>
            <input value={username} onChange={(e) => setUsername(e.target.value)} autoComplete="username" autoFocus required />
          </label>
          <label className="field"><span>Password</span>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
          </label>
          {error && <p className="login-error" role="alert">{error}</p>}
          <button type="submit" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
        </form>

        <div className="demo-accounts">
          <div className="muted small">Demo accounts (development only). Click to fill in:</div>
          {DEMO.map(([u, p, role]) => (
            <button key={u} type="button" className="demo-row" onClick={() => { setUsername(u); setPassword(p); setError(null) }}>
              <strong>{u}</strong><span>{ROLE_LABEL[role]}</span>
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
