// SHIPPING AGENT home: "where are my ships, and is my paperwork done?"
// Reads v_agent_calls (its own external view), filtered to the agent's company.
import { Link } from 'react-router-dom'
import { useAuth } from '../auth.jsx'
import { fmtTime } from '../format.js'
import { useFetch } from '../useFetch.js'

const STEPS = [
  ['Expected', 'eta', 'ETA'],
  ['Waiting', 'ata', 'Arrived'],
  ['Berthed', 'atb', 'Berthed'],
  ['Departed', 'atd', 'Departed'],
]

function Progress({ call }) {
  // a departed call has finished every step; otherwise the status is the current step
  const reached = call.call_status === 'Departed' ? STEPS.length : STEPS.findIndex(([s]) => s === call.call_status)
  return (
    <ol className="stepper" aria-label={`Status: ${call.call_status}`}>
      {STEPS.map(([status, field, label], i) => (
        <li key={status} className={i < reached ? 'done' : i === reached ? 'current' : ''}>
          <span className="step-dot" aria-hidden="true">{i < reached ? '✓' : ''}</span>
          <span className="step-name">{status}</span>
          <span className="step-time">{call[field] ? `${label} ${fmtTime(call[field])}` : '—'}</span>
        </li>
      ))}
    </ol>
  )
}

function VesselCard({ c }) {
  const etaShift = c.predicted_eta && c.eta ? (new Date(c.predicted_eta) - new Date(c.eta)) / 60000 : null
  return (
    <article className="card vessel-card">
      <header className="vessel-head">
        <div>
          <h3>{c.vessel_name}</h3>
          <div className="muted small">IMO {c.imo_number} · {c.vessel_type} · {c.flag} flag · call {c.call_id}</div>
        </div>
      </header>

      <Progress call={c} />

      <div className="vessel-facts">
        <div>
          <span className="muted small">Arrival</span>
          <div>ETA {fmtTime(c.eta)}</div>
          {c.predicted_eta && (
            <div className="small">ML predicts {fmtTime(c.predicted_eta)}
              {etaShift !== null && Math.abs(etaShift) >= 1 &&
                <span className="muted"> ({etaShift > 0 ? `${Math.round(etaShift)} min later` : `${Math.round(-etaShift)} min earlier`})</span>}
            </div>
          )}
        </div>
        <div>
          <span className="muted small">Berth</span>
          {c.berth_number
            ? <><div>{c.berth_number}</div><div className="small muted">{fmtTime(c.berth_start)} → {fmtTime(c.berth_end)}</div></>
            : <div className="muted">not allocated yet</div>}
        </div>
        <div>
          <span className="muted small">Manifests</span>
          <div>IGM {c.import_manifest ?? <span className="warn-text">not filed</span>}</div>
          <div className="small">EGM {c.export_manifest ?? <span className="muted">none</span>}</div>
        </div>
        <div>
          <span className="muted small">Cargo &amp; customs</span>
          {c.shipments === 0
            ? <div className="muted">no shipments yet</div>
            : <>
                <div>{c.shipments} shipment{c.shipments === 1 ? '' : 's'}</div>
                <div className="small">{c.customs_cleared} cleared · {c.customs_pending > 0
                  ? <span className="warn-text">{c.customs_pending} pending</span> : '0 pending'}</div>
              </>}
        </div>
      </div>

      {c.call_status !== 'Departed' && (
        <footer className="vessel-foot">
          {c.import_manifest
            ? <Link className="btn-outline" to="/upload">Upload a Bill of Lading</Link>
            : <span className="muted small">An import manifest must be filed before Bills of Lading can be added.</span>}
        </footer>
      )}
    </article>
  )
}

export default function AgentHome() {
  const { user } = useAuth()
  const calls = useFetch('/home/agent/calls')
  const rows = calls.data ?? []
  const active = rows.filter((c) => c.call_status !== 'Departed')
  const inPort = rows.filter((c) => c.call_status === 'Waiting' || c.call_status === 'Berthed')
  const pending = rows.reduce((n, c) => n + c.customs_pending, 0)

  return (
    <>
      <section className="card section agent-hello">
        <h2>{user.name}</h2>
        <p className="muted small">Your vessels at this port, from the view <code>v_agent_calls</code>. You only see your own company's port calls.</p>
      </section>

      <div className="kpi-row">
        <div className="kpi card"><span className="kpi-value">{active.length}</span><span className="kpi-label">Active calls</span><span className="kpi-note">not yet departed</span></div>
        <div className="kpi card"><span className="kpi-value">{inPort.length}</span><span className="kpi-label">In port now</span><span className="kpi-note">waiting or alongside</span></div>
        <div className="kpi card"><span className="kpi-value">{pending}</span><span className="kpi-label">Shipments in customs</span><span className="kpi-note">not cleared yet</span></div>
        <div className="kpi card"><span className="kpi-value">{rows.length - active.length}</span><span className="kpi-label">Completed calls</span><span className="kpi-note">departed</span></div>
      </div>

      {calls.error ? <p className="load-error">{calls.error}</p> : calls.loading ? <p className="muted">Loading…</p> : (
        <div className="vessel-list">
          {rows.map((c) => <VesselCard key={c.call_id} c={c} />)}
          {rows.length === 0 && <p className="muted">No port calls for your company yet.</p>}
        </div>
      )}
    </>
  )
}
