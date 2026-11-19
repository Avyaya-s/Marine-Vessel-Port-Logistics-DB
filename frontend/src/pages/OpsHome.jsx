// PORT OPERATIONS home: "which ships need my attention, and where can they go?"
// Reads v_berth_queue (its own external view) + the berth schedule.
import { useState } from 'react'
import { post } from '../api.js'
import { BerthTimeline, Legend, STATUS_ORDER } from '../charts.jsx'
import { Notice, StatusBadge } from '../components.jsx'
import { fmtTime } from '../format.js'
import { useFetch } from '../useFetch.js'

const STATE_CLASS = { 'Needs berth': 'q-needs', 'Waiting for berth': 'q-waiting', 'Booked': 'q-booked' }

export default function OpsHome() {
  const queue = useFetch('/home/operations/queue')
  const calls = useFetch('/port-calls')
  const berths = useFetch('/berths')
  const [busy, setBusy] = useState(null)
  const [notice, setNotice] = useState(null)

  const q = queue.data ?? []
  const needs = q.filter((r) => r.queue_state === 'Needs berth')
  const waiting = q.filter((r) => r.call_status === 'Waiting')
  const free = (berths.data ?? []).filter((b) => !b.occupied_by).length

  async function allocate(r) {
    setBusy(r.call_id)
    try {
      const a = await post(`/port-calls/${r.call_id}/allocate`)
      setNotice({ kind: 'ok', title: `${r.vessel_name} → berth ${a.berth}`,
                  text: `${fmtTime(a.berth_start)} → ${fmtTime(a.berth_end)}, the earliest free berth that fits.` })
      queue.reload(); calls.reload(); berths.reload()
    } catch (e) {
      setNotice({ kind: 'error', title: `Could not allocate ${r.vessel_name}`, text: e.message })
    } finally {
      setBusy(null)
    }
  }

  return (
    <>
      <div className="kpi-row">
        <div className="kpi card"><span className="kpi-value">{needs.length}</span><span className="kpi-label">Need a berth</span>
          <span className="kpi-note">no berth booked yet</span></div>
        <div className="kpi card"><span className="kpi-value">{waiting.length}</span><span className="kpi-label">Waiting at anchor</span>
          <span className="kpi-note">arrived, not yet alongside</span></div>
        <div className="kpi card"><span className="kpi-value">{free} / {berths.data?.length ?? '–'}</span><span className="kpi-label">Berths free now</span>
          <span className="kpi-note">no ship alongside</span></div>
        <div className="kpi card"><span className="kpi-value">{q.length}</span><span className="kpi-label">Ships in the queue</span>
          <span className="kpi-note">expected or waiting</span></div>
      </div>

      <section className="card section">
        <div className="section-head">
          <div>
            <h2>Berth queue</h2>
            <p className="muted small">From the view <code>v_berth_queue</code>: every ship not yet berthed, in the order it will be ready.</p>
          </div>
        </div>
        <Notice notice={notice} onClose={() => setNotice(null)} />
        {queue.error ? <p className="load-error">{queue.error}</p> : queue.loading ? <p className="muted">Loading…</p> : (
          <div className="queue">
            {q.map((r) => (
              <div key={r.call_id} className={`queue-item ${STATE_CLASS[r.queue_state]}`}>
                <div className="queue-main">
                  <div className="queue-title">
                    <strong>{r.vessel_name}</strong>
                    <span className={`queue-state ${STATE_CLASS[r.queue_state]}`}>{r.queue_state}</span>
                  </div>
                  <div className="muted small">{r.vessel_type} · {r.loa} m · {r.draft} m draft · agent {r.agent}</div>
                </div>
                <div className="queue-cell"><span className="muted small">Ready</span>{fmtTime(r.ready_time)}
                  <span className="muted small">{r.ata ? 'arrived (ATA)' : r.predicted_eta ? 'ML predicted ETA' : 'agent ETA'}</span></div>
                <div className="queue-cell"><span className="muted small">Berth</span>
                  {r.berth_number ? <>{r.berth_number} <span className="muted small">{fmtTime(r.berth_start)}</span></> : <span className="muted">none</span>}</div>
                <div className="queue-cell"><span className="muted small">Fits</span>
                  {r.suitable_berths === 0
                    ? <span className="fit-none">⚠ no berth fits</span>
                    : `${r.suitable_berths} berth${r.suitable_berths === 1 ? '' : 's'}`}</div>
                <div className="queue-action">
                  {!r.berth_number && r.suitable_berths > 0 && (
                    <button onClick={() => allocate(r)} disabled={busy !== null}>{busy === r.call_id ? 'Allocating…' : 'Allocate berth'}</button>
                  )}
                  {r.berth_number && <StatusBadge status={r.call_status} />}
                </div>
              </div>
            ))}
            {q.length === 0 && <p className="muted">No ships in the queue.</p>}
          </div>
        )}
      </section>

      <section className="panel-dark">
        <div className="panel-head"><h3><span className="accent">Berth</span> Schedule</h3></div>
        <Legend items={STATUS_ORDER} />
        {calls.data && berths.data ? <BerthTimeline berths={berths.data} calls={calls.data} /> : <p className="on-dark-muted">Loading…</p>}
      </section>
    </>
  )
}
