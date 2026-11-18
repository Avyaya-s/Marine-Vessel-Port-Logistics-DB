import { useEffect, useState } from 'react'
import { NavLink, Navigate, Route, Routes, useLocation } from 'react-router-dom'
import Ask from './pages/Ask.jsx'
import ComingSoon from './pages/ComingSoon.jsx'
import Customs from './pages/Customs.jsx'
import Dashboard from './pages/Dashboard.jsx'
import PortCalls from './pages/PortCalls.jsx'
import { useFetch } from './useFetch.js'

const NAV = [
  { group: 'Operations', items: [
    { to: '/dashboard',  label: 'Dashboard',  icon: '◧' },
    { to: '/port-calls', label: 'Port Calls', icon: '⚓' },
  ]},
  { group: 'Customs', items: [
    { to: '/customs',    label: 'Pending Customs', icon: '▤' },
  ]},
  { group: 'Assistant', items: [
    { to: '/ask',    label: 'Ask the Database', icon: '?' },
  ]},
  { group: 'Coming soon', items: [
    { to: '/map',    label: 'Live Map', icon: '◎', soon: true },
    { to: '/upload', label: 'Upload',   icon: '⇪', soon: true },
  ]},
]
const TITLES = Object.fromEntries(NAV.flatMap((g) => g.items.map((i) => [i.to, i.label])))

// light by default; the choice is remembered in this browser only
function useTheme() {
  const [theme, setTheme] = useState(() => {
    try { return localStorage.getItem('theme') || 'light' } catch { return 'light' }
  })
  useEffect(() => {
    document.documentElement.dataset.theme = theme
    try { localStorage.setItem('theme', theme) } catch { /* storage blocked: ignore */ }
  }, [theme])
  return [theme, () => setTheme(theme === 'light' ? 'dark' : 'light')]
}

function SidebarProfile() {
  const calls = useFetch('/port-calls')
  const berths = useFetch('/berths')
  const customs = useFetch('/customs/pending')
  const vessels = new Set((calls.data ?? []).map((c) => c.vessel_name)).size
  return (
    <div className="profile">
      <div className="avatar" aria-hidden="true">HM</div>
      <div className="profile-name">Harbour Master</div>
      <div className="profile-role">Port Control</div>
      <div className="profile-stats">
        <div><strong>{vessels}</strong><span>Vessels</span></div>
        <div><strong>{berths.data?.length ?? '–'}</strong><span>Berths</span></div>
        <div><strong>{customs.data?.length ?? '–'}</strong><span>Pending</span></div>
      </div>
    </div>
  )
}

export default function App() {
  const [theme, toggleTheme] = useTheme()
  const [refreshKey, setRefreshKey] = useState(0)
  const [updated, setUpdated] = useState(new Date())
  const health = useFetch('/health')
  const { pathname } = useLocation()
  const title = TITLES[pathname] ?? 'Dashboard'

  function refresh() {
    setRefreshKey((k) => k + 1)   // remounts the page, which re-fetches its data
    setUpdated(new Date())
  }

  return (
    <div className="app">
      <header className="topbar">
        <div className="topbar-brand"><span className="brand-mark">⚓</span> Port Logistics</div>
        <div className="topbar-right">
          <span className={`api-status ${health.error ? 'down' : 'up'}`}>
            <span className="api-dot" />{health.error ? 'API offline' : health.loading ? 'Connecting…' : 'API connected'}
          </span>
          <button className="icon-btn" onClick={toggleTheme} aria-label="Toggle dark mode" title="Toggle dark mode">
            {theme === 'light' ? '☾' : '☀'}
          </button>
        </div>
      </header>

      <div className="body">
        <aside className="sidebar">
          <SidebarProfile key={refreshKey} />
          <nav>
            {NAV.map((g) => (
              <div key={g.group} className="nav-group">
                <div className="nav-heading">{g.group}</div>
                {g.items.map((n) => (
                  <NavLink key={n.to} to={n.to} className={({ isActive }) => `nav-link${isActive ? ' active' : ''}`}>
                    <span className="nav-icon" aria-hidden="true">{n.icon}</span>
                    <span className="nav-text">{n.label}</span>
                    {n.soon && <span className="soon">soon</span>}
                  </NavLink>
                ))}
              </div>
            ))}
          </nav>
          <div className="sidebar-foot">PostgreSQL · FastAPI · React</div>
        </aside>

        <main className="content">
          <div className="page-head">
            <div>
              <h1>{title}</h1>
              <div className="crumbs"><span className="crumb-home">⚓ Port Logistics</span> / {title}</div>
            </div>
            <div className="page-actions">
              <span className="muted small">Updated {updated.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' })}</span>
              <button className="btn-outline" onClick={refresh}>Refresh</button>
            </div>
          </div>

          <div className="page" key={refreshKey}>
            <Routes>
              <Route path="/" element={<Navigate to="/dashboard" replace />} />
              <Route path="/dashboard" element={<Dashboard />} />
              <Route path="/port-calls" element={<PortCalls />} />
              <Route path="/customs" element={<Customs />} />
              <Route path="/map" element={
                <ComingSoon title="Live vessel map" phase="Phase 3-4 · MongoDB">
                  Latest AIS position of every ship on a Leaflet map, from the MongoDB ship_location
                  time-series collection, joined with vessel names from PostgreSQL by MMSI. Arrival at the
                  anchorage (a $geoWithin geofence) will set the port call's ATA automatically.
                </ComingSoon>} />
              <Route path="/upload" element={
                <ComingSoon title="Document upload" phase="Phase 7 · NLP">
                  Upload a Bill of Lading or invoice PDF; fields are extracted (pdfplumber + OCR), an HS code
                  is suggested, and after you confirm them the shipment is inserted.
                </ComingSoon>} />
              <Route path="/ask" element={<Ask />} />
              <Route path="*" element={<Navigate to="/dashboard" replace />} />
            </Routes>
          </div>
        </main>
      </div>
    </div>
  )
}
