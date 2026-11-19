// CUSTOMS OFFICER home: an inbox-style workbench.
// Left: the queue (v_pending_customs, riskiest first).  Right: one filing in
// full, with its inspection history and the two actions an officer takes:
// record an inspection (record_inspection) and clear it (clear_customs).
import { useEffect, useState } from 'react'
import { get, post } from '../api.js'
import { RiskBadge, StatusBadge } from '../components.jsx'
import { fmtMoney } from '../format.js'
import { useFetch } from '../useFetch.js'
import { Notice } from '../components.jsx'

const RESULT_CLASS = { Clear: 'check-ok', Discrepancy: 'check-error', Pending: 'check-warning' }

function Detail({ filingNo, onChanged }) {
  const [d, setD] = useState(null)
  const [error, setError] = useState(null)
  const [result, setResult] = useState('Clear')
  const [remarks, setRemarks] = useState('')
  const [duty, setDuty] = useState('')
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState(null)

  const load = () => get(`/customs/${filingNo}`).then((x) => { setD(x); setError(null) }).catch((e) => setError(e.message))
  useEffect(() => { setD(null); setNotice(null); setDuty(''); setRemarks(''); load() }, [filingNo])

  async function act(fn, okTitle) {
    setBusy(true)
    try {
      const r = await fn()
      setNotice({ kind: 'ok', title: okTitle(r), text: 'Saved in one transaction.' })
      await load()
      onChanged()
    } catch (e) {
      setNotice({ kind: 'error', title: 'Not saved, nothing was changed', text: e.message })
    } finally {
      setBusy(false)
    }
  }

  if (error) return <p className="load-error">{error}</p>
  if (!d) return <p className="muted">Loading…</p>
  const last = d.inspections.at(-1)

  return (
    <div className="detail">
      <div className="detail-head">
        <div>
          <h2>{d.filing_no}</h2>
          <div className="muted small">{d.filing_type} · filed {d.filing_date} · B/L {d.shipment_no}</div>
        </div>
        <div className="detail-badges"><RiskBadge score={d.risk_score} /><StatusBadge status={d.filing_status} /></div>
      </div>
      <Notice notice={notice} onClose={() => setNotice(null)} />

      <dl className="facts">
        <div><dt>Cargo</dt><dd>{d.cargo_description}</dd></div>
        <div><dt>HS code</dt><dd>{d.hs_code}</dd></div>
        <div><dt>Origin</dt><dd>{d.origin_port}</dd></div>
        <div><dt>Declared value</dt><dd>{fmtMoney(d.declared_value)}</dd></div>
        <div><dt>Quantity / weight</dt><dd>{d.cargo_quantity} pkgs · {Number(d.gross_weight).toLocaleString('en-IN')} kg</dd></div>
        <div><dt>Shipper</dt><dd>{d.shipper}</dd></div>
        <div><dt>Consignee</dt><dd>{d.consignee}{d.iec_code && <span className="muted small"> · IEC {d.iec_code}</span>}</dd></div>
        <div><dt>Vessel</dt><dd>{d.vessel_name} <span className="muted small">call {d.call_id} · {d.manifest_no}</span></dd></div>
      </dl>

      <h3 className="sub-h">Containers</h3>
      {d.containers.length === 0 ? <p className="muted small">None (bulk cargo).</p> : (
        <ul className="plain-list">
          {d.containers.map((c) => (
            <li key={c.container_no}><strong>{c.container_no}</strong> <span className="muted small">{c.size} ft {c.iso_type} · seal {c.seal_no ?? '—'}</span>
              <span className="pill-status">{c.container_status}</span></li>
          ))}
        </ul>
      )}

      <h3 className="sub-h">Inspection history</h3>
      {d.inspections.length === 0 ? <p className="muted small">No inspections yet.</p> : (
        <ol className="checks history">
          {d.inspections.map((i) => (
            <li key={i.inspection_no} className={`check ${RESULT_CLASS[i.result]}`}>
              <span className="check-icon" aria-hidden="true">{i.inspection_no}</span>
              <span><strong>{i.result}</strong> · {i.inspection_date} · {i.officer_name}{i.remarks && <div className="muted small">{i.remarks}</div>}</span>
            </li>
          ))}
        </ol>
      )}

      <div className="actions">
        <form className="action-box" onSubmit={(e) => { e.preventDefault()
          act(() => post(`/customs/${d.filing_no}/inspections`, { result, remarks }),
              (r) => `Inspection #${r.inspection_no} recorded, filing is now ${r.filing_status}`) }}>
          <h3 className="sub-h">Record inspection</h3>
          <div className="action-row">
            <select value={result} onChange={(e) => setResult(e.target.value)} aria-label="Result">
              <option>Clear</option><option>Discrepancy</option><option>Pending</option>
            </select>
            <input value={remarks} onChange={(e) => setRemarks(e.target.value)} placeholder="Remarks" aria-label="Remarks" />
            <button type="submit" disabled={busy}>Record</button>
          </div>
        </form>
        <form className="action-box" onSubmit={(e) => { e.preventDefault()
          act(() => post(`/customs/${d.filing_no}/clear`, { duty: Number(duty) }),
              (r) => `${d.filing_no} cleared, ${r.containers_released} container(s) released`) }}>
          <h3 className="sub-h">Clear filing</h3>
          <div className="action-row">
            <input type="number" min="0" step="0.01" value={duty} onChange={(e) => setDuty(e.target.value)} placeholder="Duty ₹" aria-label="Duty" required />
            <button type="submit" disabled={busy}>Clear</button>
          </div>
          {last && last.result !== 'Clear' &&
            <p className="muted small">Latest inspection is {last.result}: clearing will be refused until an inspection comes back Clear.</p>}
        </form>
      </div>
    </div>
  )
}

export default function CustomsHome() {
  const workload = useFetch('/customs/workload')
  const queue = useFetch('/customs/pending')
  const [selected, setSelected] = useState(null)
  const w = workload.data ?? {}
  const items = queue.data ?? []
  const current = selected ?? items[0]?.filing_no

  function changed() { workload.reload(); queue.reload() }

  return (
    <>
      <div className="kpi-row">
        <div className="kpi card"><span className="kpi-value">{w.pending_total ?? '–'}</span><span className="kpi-label">Pending filings</span>
          <span className="kpi-note">{w.filed ?? 0} filed · {w.under_review ?? 0} under review · {w.held ?? 0} held</span></div>
        <div className="kpi card"><span className="kpi-value">{w.high_risk ?? '–'}</span><span className="kpi-label">High risk</span>
          <span className="kpi-note">risk score ≥ 0.70 · {w.unscored ?? 0} not scored</span></div>
        <div className="kpi card"><span className="kpi-value">{w.awaiting_inspection ?? '–'}</span><span className="kpi-label">Awaiting inspection</span>
          <span className="kpi-note">latest inspection still pending</span></div>
        <div className="kpi card"><span className="kpi-value">{fmtMoney(w.pending_value)}</span><span className="kpi-label">Value held at port</span>
          <span className="kpi-note">{w.cleared_total ?? 0} filings cleared so far</span></div>
      </div>

      <div className="workbench">
        <section className="card inbox">
          <div className="inbox-head"><h2>Work queue</h2><span className="muted small">riskiest first</span></div>
          {queue.loading ? <p className="muted pad">Loading…</p> : items.length === 0 ? <p className="muted pad">Nothing pending.</p> : (
            <ul>
              {items.map((f) => (
                <li key={f.filing_no}>
                  <button className={`inbox-item${f.filing_no === current ? ' selected' : ''}`} onClick={() => setSelected(f.filing_no)}>
                    <span className="inbox-top"><strong>{f.filing_no}</strong><RiskBadge score={f.risk_score} /></span>
                    <span className="inbox-cargo">{f.cargo_description}</span>
                    <span className="inbox-meta"><StatusBadge status={f.filing_status} /><span className="muted small">{f.days_pending} days</span></span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </section>
        <section className="card section">
          {current ? <Detail filingNo={current} onChanged={changed} /> : <p className="muted">Select a filing.</p>}
        </section>
      </div>
    </>
  )
}
