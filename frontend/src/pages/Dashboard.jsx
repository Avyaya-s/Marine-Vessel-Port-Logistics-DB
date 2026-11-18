import { useState } from 'react'
import { BerthTimeline, Legend, MeterList, RankedBars, STATUS_ORDER, SegmentedBar } from '../charts.jsx'
import { StatusBadge } from '../components.jsx'
import { fmtDuration, fmtTime } from '../format.js'
import { useFetch } from '../useFetch.js'

const avg = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null)

function Kpi({ value, label, note, meter }) {
  return (
    <div className="kpi card">
      <span className="kpi-value">{value}</span>
      <span className="kpi-label">{label}</span>
      {meter !== undefined && (
        <div className="kpi-meter" role="img" aria-label={`${Math.round(meter * 100)}%`}>
          <div className="kpi-meter-fill" style={{ width: `${meter * 100}%` }} />
        </div>
      )}
      <span className="kpi-note">{note}</span>
    </div>
  )
}

function Card({ title, accent, subtitle, children, state }) {
  return (
    <section className="card chart-card">
      <h3><span className="accent">{accent}</span> {title}</h3>
      {subtitle && <p className="muted small card-sub">{subtitle}</p>}
      {state?.error ? <p className="load-error">Could not load: {state.error}</p>
        : state?.loading ? <p className="muted">Loading…</p>
        : children}
    </section>
  )
}

export default function Dashboard() {
  const summary = useFetch('/port-calls/summary')
  const calls = useFetch('/port-calls')
  const berths = useFetch('/berths')
  const waits = useFetch('/waiting-times')
  const customs = useFetch('/customs/pending')
  const [view, setView] = useState('timeline')

  const s = summary.data ?? {}
  const berthList = berths.data ?? []
  const occupied = berthList.filter((b) => b.occupied_by).length
  const waitRows = waits.data ?? []
  const waited = waitRows.map((w) => w.waiting_time).filter((x) => x !== null)
  const delays = waitRows.map((w) => w.berthing_delay).filter((x) => x !== null)
  const agentErr = waitRows.map((w) => w.agent_eta_error).filter((x) => x !== null).map(Math.abs)
  const modelErr = waitRows.map((w) => w.model_eta_error).filter((x) => x !== null).map(Math.abs)
  const pending = customs.data ?? []
  const highRisk = pending.filter((f) => f.risk_score >= 0.7).length
  const totalCalls = STATUS_ORDER.reduce((n, k) => n + (s[k] ?? 0), 0)

  return (
    <>
      <div className="kpi-row">
        <Kpi value={(s.Waiting ?? 0) + (s.Berthed ?? 0)} label="Ships in port"
             note={`${s.Waiting ?? 0} at anchor · ${s.Berthed ?? 0} alongside`} />
        <Kpi value={`${occupied} / ${berthList.length}`} label="Berths occupied"
             meter={berthList.length ? occupied / berthList.length : 0}
             note={`${berthList.length - occupied} free right now`} />
        <Kpi value={fmtDuration(avg(waited))} label="Avg anchorage wait"
             note={`over ${waited.length} berthed call${waited.length === 1 ? '' : 's'}`} />
        <Kpi value={pending.length} label="Pending customs"
             note={`${highRisk} high risk (score ≥ 0.70)`} />
      </div>

      <section className="panel-dark">
        <div className="panel-head">
          <h3><span className="accent">Berth</span> Schedule</h3>
          <div className="tabs" role="tablist">
            <button role="tab" aria-selected={view === 'timeline'} className={view === 'timeline' ? 'tab active' : 'tab'} onClick={() => setView('timeline')}>Timeline view</button>
            <button role="tab" aria-selected={view === 'table'} className={view === 'table' ? 'tab active' : 'tab'} onClick={() => setView('table')}>Table view</button>
          </div>
        </div>
        <Legend items={STATUS_ORDER} />

        {calls.error || berths.error ? <p className="load-error">Could not load: {calls.error || berths.error}. Is the backend running?</p>
          : calls.loading || berths.loading ? <p className="on-dark-muted">Loading…</p>
          : view === 'timeline' ? <BerthTimeline berths={berthList} calls={calls.data} />
          : (
            <table className="table-dark">
              <thead><tr><th>Berth</th><th>Vessel</th><th>Status</th><th>Planned start</th><th>Planned end</th></tr></thead>
              <tbody>
                {calls.data.filter((c) => c.berth_number).sort((a, b) => a.berth_number.localeCompare(b.berth_number) || a.berth_start.localeCompare(b.berth_start)).map((c) => (
                  <tr key={c.call_id}>
                    <td>{c.berth_number}</td><td>{c.vessel_name}</td><td><StatusBadge status={c.call_status} /></td>
                    <td>{fmtTime(c.berth_start)}</td><td>{c.berth_end ? fmtTime(c.berth_end) : 'open-ended'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

        <div className="panel-stats">
          <div><span className="ps-value">{totalCalls}</span><span className="ps-label">Port calls</span></div>
          <div><span className="ps-value">{fmtDuration(avg(waited))}</span><span className="ps-label">Avg wait at anchor</span></div>
          <div><span className="ps-value">{fmtDuration(avg(delays))}</span><span className="ps-label">Avg berthing delay vs plan</span></div>
          <div>
            <span className="ps-value">{fmtDuration(avg(modelErr))} <span className="ps-vs">vs {fmtDuration(avg(agentErr))}</span></span>
            <span className="ps-label">Avg ETA error: ML model vs agent</span>
          </div>
        </div>
      </section>

      <div className="card-row">
        <Card accent="Port call" title="status" subtitle="Set by a trigger from actual arrival / berthing / departure times." state={summary}>
          <SegmentedBar counts={s} thin />
          <ul className="status-list">
            {STATUS_ORDER.map((k) => (
              <li key={k}><StatusBadge status={k} /><span>{s[k] ?? 0}</span></li>
            ))}
          </ul>
        </Card>

        <Card accent="Waiting" title="at anchorage" subtitle="atb − ata, from the view v_waiting_time." state={waits}>
          <RankedBars rows={waitRows} />
        </Card>

        <Card accent="Customs" title="risk queue" subtitle="Uncleared filings, riskiest first (v_pending_customs)." state={customs}>
          <MeterList rows={pending} />
        </Card>
      </div>
    </>
  )
}
