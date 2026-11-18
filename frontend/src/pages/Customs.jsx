import { useState } from 'react'
import { post } from '../api.js'
import { Notice, RiskBadge, Section, StatusBadge } from '../components.jsx'
import { fmtMoney } from '../format.js'
import { useFetch } from '../useFetch.js'

export default function Customs() {
  const pending = useFetch('/customs/pending')
  const [duty, setDuty] = useState({})          // filing_no -> typed duty
  const [busy, setBusy] = useState(null)
  const [notice, setNotice] = useState(null)

  async function clear(f) {
    const value = duty[f.filing_no]
    if (value === undefined || value === '') {
      setNotice({ kind: 'error', title: 'Enter the duty first', text: `Type the assessed duty for ${f.filing_no}.` })
      return
    }
    setBusy(f.filing_no)
    try {
      const r = await post(`/customs/${f.filing_no}/clear`, { duty: Number(value) })
      setNotice({ kind: 'ok', title: `${f.filing_no} cleared`,
                  text: `Filing marked Cleared, duty ${fmtMoney(Number(value))} recorded, ${r.containers_released} container(s) released, all in one transaction.` })
      pending.reload()
    } catch (e) {
      setNotice({ kind: 'error', title: 'Clearance failed, nothing was changed',
                  text: `${e.message}. The transaction was rolled back, so the filing, duty and containers are exactly as before.` })
      pending.reload()
    } finally {
      setBusy(null)
    }
  }

  return (
    <Section title="Pending customs" subtitle="From the view v_pending_customs, riskiest first. Clearing runs the clear_customs() transaction (all-or-nothing)."
             loading={pending.loading} error={pending.error}>
      <Notice notice={notice} onClose={() => setNotice(null)} />
      {pending.data?.length === 0 ? <p className="muted">Nothing pending. Every filing is cleared.</p> : (
        <table>
          <thead>
            <tr><th>Filing</th><th>Risk</th><th>Status</th><th>Cargo</th><th>Consignee</th><th>Declared</th><th>Containers</th><th>Last inspection</th><th>Clear</th></tr>
          </thead>
          <tbody>
            {pending.data?.map((f) => (
              <tr key={f.filing_no}>
                <td>
                  <strong className="nowrap">{f.filing_no}</strong>
                  <div className="muted small">{f.filing_type} · {f.days_pending} days</div>
                </td>
                <td><RiskBadge score={f.risk_score} /></td>
                <td><StatusBadge status={f.filing_status} /></td>
                <td>
                  {f.cargo_description}
                  <div className="muted small">HS {f.hs_code} · from {f.origin_port} · {f.vessel_name}</div>
                </td>
                <td>{f.consignee}</td>
                <td>{fmtMoney(f.declared_value)}</td>
                <td className="center">{f.containers}</td>
                <td>{f.last_inspection_result ?? <span className="muted">none</span>}</td>
                <td>
                  <div className="clear-form">
                    <input type="number" min="0" placeholder="Duty ₹"
                           value={duty[f.filing_no] ?? ''}
                           onChange={(e) => setDuty({ ...duty, [f.filing_no]: e.target.value })} />
                    <button onClick={() => clear(f)} disabled={busy !== null}>
                      {busy === f.filing_no ? 'Clearing…' : 'Clear'}
                    </button>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Section>
  )
}
