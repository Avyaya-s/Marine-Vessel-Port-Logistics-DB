import { useState } from 'react'
import { post } from '../api.js'
import { Notice, Section, StatusBadge } from '../components.jsx'
import { fmtTime } from '../format.js'
import { useFetch } from '../useFetch.js'

export default function PortCalls() {
  const calls = useFetch('/port-calls')
  const [busy, setBusy] = useState(null)       // call_id being allocated
  const [notice, setNotice] = useState(null)

  async function allocate(call) {
    setBusy(call.call_id)
    try {
      const r = await post(`/port-calls/${call.call_id}/allocate`)
      setNotice({ kind: 'ok', title: `Berth ${r.berth} booked for ${call.vessel_name}`,
                  text: `${fmtTime(r.berth_start)} → ${fmtTime(r.berth_end)} (allocate_berth picked the earliest free berth that fits).` })
      calls.reload()
    } catch (e) {
      setNotice({ kind: 'error', title: 'The database refused the allocation', text: e.message })
    } finally {
      setBusy(null)
    }
  }

  return (
    <Section title="Port calls" subtitle="Every ship visit. Calls without a berth can be allocated with the allocate_berth() stored procedure."
             loading={calls.loading} error={calls.error}>
      <Notice notice={notice} onClose={() => setNotice(null)} />
      <table>
        <thead>
          <tr><th>#</th><th>Vessel</th><th>Agent</th><th>Status</th><th>ETA</th><th>Berth</th><th>Planned window</th><th></th></tr>
        </thead>
        <tbody>
          {calls.data?.map((c) => (
            <tr key={c.call_id}>
              <td className="muted">{c.call_id}</td>
              <td>
                <strong>{c.vessel_name}</strong>
                <div className="muted small">{c.vessel_type} · {c.loa} m · {c.draft} m draft</div>
              </td>
              <td>{c.agent}</td>
              <td><StatusBadge status={c.call_status} /></td>
              <td>
                {fmtTime(c.eta)}
                {c.predicted_eta && <div className="muted small">ML: {fmtTime(c.predicted_eta)}</div>}
              </td>
              <td>{c.berth_number ?? <span className="muted">none</span>}</td>
              <td>{c.berth_start ? `${fmtTime(c.berth_start)} → ${fmtTime(c.berth_end)}` : '—'}</td>
              <td className="right">
                {!c.berth_number && c.call_status !== 'Departed' && (
                  <button onClick={() => allocate(c)} disabled={busy !== null}>
                    {busy === c.call_id ? 'Allocating…' : 'Allocate berth'}
                  </button>
                )}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Section>
  )
}
