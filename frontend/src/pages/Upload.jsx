import { useEffect, useRef, useState } from 'react'
import { get, post } from '../api.js'
import { Notice } from '../components.jsx'
import { useFetch } from '../useFetch.js'

const ICON = { ok: '✓', info: 'i', warning: '!', error: '✕' }

// multipart upload (api.js only does JSON)
async function uploadPdf(file) {
  const form = new FormData()
  form.append('file', file)
  const res = await fetch('/api/documents/extract', { method: 'POST', body: form })
  const body = await res.json().catch(() => null)
  if (!res.ok) throw new Error(typeof body?.detail === 'string' ? body.detail : `Upload failed (HTTP ${res.status})`)
  return body
}

function Checks({ checks }) {
  return (
    <ul className="checks">
      {checks.map((c, i) => (
        <li key={i} className={`check check-${c.level}`}>
          <span className="check-icon" aria-hidden="true">{ICON[c.level]}</span>
          <span><span className="sr-only">{c.level}: </span>{c.text}</span>
        </li>
      ))}
    </ul>
  )
}

function Field({ label, children, wide }) {
  return <label className={`field${wide ? ' field-wide' : ''}`}><span>{label}</span>{children}</label>
}

function ReviewForm({ result, onSaved }) {
  const f = result.fields
  const [form, setForm] = useState({
    manifest_no: result.suggested_manifest ?? '',
    shipment_no: f.shipment_no, shipper_name: f.shipper_name, consignee_name: f.consignee_name,
    origin_port: f.origin_port, cargo_description: f.cargo_description, hs_code: f.hs_code,
    cargo_quantity: f.cargo_quantity, gross_weight: f.gross_weight,
  })
  const [containers, setContainers] = useState(result.containers)
  const [suggestions, setSuggestions] = useState(result.hs_suggestions)
  const [busy, setBusy] = useState(false)
  const [notice, setNotice] = useState(null)
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value })
  const setC = (i, k, v) => setContainers(containers.map((c, j) => (j === i ? { ...c, [k]: v } : c)))

  async function resuggest() {
    if (form.cargo_description.trim().length > 2) {
      setSuggestions(await get(`/documents/hs-suggest?q=${encodeURIComponent(form.cargo_description)}`).catch(() => suggestions))
    }
  }

  async function confirm(e) {
    e.preventDefault()
    setBusy(true)
    try {
      const r = await post('/documents/confirm', {
        ...form,
        cargo_quantity: Number(form.cargo_quantity),
        gross_weight: Number(form.gross_weight),
        containers,
      })
      setNotice({ kind: 'ok', title: `${r.shipment_no} saved`,
                  text: `Shipment, ${r.containers} container link(s) and any new companies were inserted in one transaction.` })
      onSaved()
    } catch (err) {
      setNotice({ kind: 'error', title: 'Not saved, nothing was changed', text: `${err.message}. The whole insert was rolled back.` })
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="card section review" onSubmit={confirm}>
      <div className="section-head">
        <div>
          <h2>Review and confirm</h2>
          <p className="muted small">Check every field against the document. Nothing is saved until you confirm.</p>
        </div>
      </div>
      <Notice notice={notice} onClose={() => setNotice(null)} />

      <div className="form-grid">
        <Field label="B/L number"><input value={form.shipment_no} onChange={set('shipment_no')} required /></Field>
        <Field label="Import manifest">
          <select value={form.manifest_no} onChange={set('manifest_no')} required>
            <option value="">Choose…</option>
            {result.manifests.map((m) => (
              <option key={m.manifest_no} value={m.manifest_no}>{m.manifest_no} · {m.vessel_name} (call {m.call_id})</option>
            ))}
          </select>
        </Field>
        <Field label="Shipper"><input value={form.shipper_name} onChange={set('shipper_name')} required /></Field>
        <Field label="Consignee"><input value={form.consignee_name} onChange={set('consignee_name')} required /></Field>
        <Field label="Origin port (UN/LOCODE)"><input value={form.origin_port} onChange={set('origin_port')} maxLength={5} required /></Field>
        <Field label="Packages"><input type="number" min="1" value={form.cargo_quantity} onChange={set('cargo_quantity')} required /></Field>
        <Field label="Gross weight (kg)"><input type="number" min="0.01" step="0.01" value={form.gross_weight} onChange={set('gross_weight')} required /></Field>
        <Field label="HS code"><input value={form.hs_code} onChange={set('hs_code')} pattern="\d{6}(\d{2})?" title="6 or 8 digits" required /></Field>
        <Field label="Cargo description" wide>
          <textarea rows="2" value={form.cargo_description} onChange={set('cargo_description')} onBlur={resuggest} required />
        </Field>
      </div>

      <div className="hs-suggest">
        <span className="muted small">Suggested HS codes (semantic match on the description):</span>
        <div className="chips">
          {suggestions.map((s) => (
            <button type="button" key={s.hs_code} className={`chip${form.hs_code.startsWith(s.hs_code) ? ' chip-on' : ''}`}
                    onClick={() => setForm({ ...form, hs_code: s.hs_code })}
                    title={`similarity ${s.score}`}>
              <strong>{s.hs_code}</strong> {s.description} <span className="chip-score">{Math.round(s.score * 100)}%</span>
            </button>
          ))}
        </div>
      </div>

      <h3 className="sub-h">Containers</h3>
      {containers.length === 0 ? <p className="muted small">None (bulk cargo).</p> : (
        <table className="table-edit">
          <thead><tr><th>Container no.</th><th>ISO type</th><th>Seal no.</th><th /></tr></thead>
          <tbody>
            {containers.map((c, i) => (
              <tr key={i}>
                <td><input value={c.container_no} onChange={(e) => setC(i, 'container_no', e.target.value.toUpperCase())} /></td>
                <td><input value={c.iso_type} onChange={(e) => setC(i, 'iso_type', e.target.value.toUpperCase())} /></td>
                <td><input value={c.seal_no} onChange={(e) => setC(i, 'seal_no', e.target.value)} /></td>
                <td><button type="button" className="btn-ghost" onClick={() => setContainers(containers.filter((_, j) => j !== i))}>Remove</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <button type="button" className="btn-ghost add-row"
              onClick={() => setContainers([...containers, { container_no: '', iso_type: '', seal_no: '' }])}>+ Add container</button>

      <div className="confirm-row">
        <button type="submit" disabled={busy}>{busy ? 'Saving…' : 'Confirm and save shipment'}</button>
      </div>
    </form>
  )
}

export default function Upload() {
  const samples = useFetch('/documents/samples')
  const fileInput = useRef(null)
  const [busy, setBusy] = useState(null)        // file name being read
  const [error, setError] = useState(null)
  const [result, setResult] = useState(null)
  const [drag, setDrag] = useState(false)
  const [version, setVersion] = useState(0)     // remount the form for each new document

  async function run(file) {
    if (!file) return
    setBusy(file.name); setError(null); setResult(null)
    try {
      setResult(await uploadPdf(file))
      setVersion((v) => v + 1)
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(null)
    }
  }

  async function trySample(name) {
    const blob = await (await fetch(`/api/documents/samples/${name}`)).blob()
    run(new File([blob], name, { type: 'application/pdf' }))
  }

  // /upload?sample=bl_shenzhen_solar.pdf runs that sample straight away (demo link).
  // React's StrictMode runs effects twice in development, so a ref makes sure
  // the (slow, LLM-backed) extraction is only started once.
  const started = useRef(false)
  useEffect(() => {
    const name = new URLSearchParams(window.location.search).get('sample')
    if (name && !started.current) {
      started.current = true
      trySample(name)
    }
  }, [])

  return (
    <>
      <section className="card section">
        <div className="section-head">
          <div>
            <h2>Upload a Bill of Lading</h2>
            <p className="muted small">
              The PDF's text is read, a local LLM extracts the fields, container numbers are matched exactly,
              and HS codes are suggested from the cargo description. You review everything before it is saved.
            </p>
          </div>
        </div>

        <div className={`dropzone${drag ? ' drag' : ''}`}
             onDragOver={(e) => { e.preventDefault(); setDrag(true) }}
             onDragLeave={() => setDrag(false)}
             onDrop={(e) => { e.preventDefault(); setDrag(false); run(e.dataTransfer.files[0]) }}
             onClick={() => fileInput.current?.click()}
             role="button" tabIndex={0}
             onKeyDown={(e) => (e.key === 'Enter' || e.key === ' ') && fileInput.current?.click()}>
          <input ref={fileInput} type="file" accept="application/pdf,.pdf" hidden
                 onChange={(e) => { run(e.target.files[0]); e.target.value = '' }} />
          <div className="dz-icon" aria-hidden="true">⇪</div>
          <div><strong>Drop a PDF here</strong> or click to choose · max 5 MB</div>
        </div>

        {samples.data?.length > 0 && (
          <div className="samples">
            <span className="muted small">Or try a sample:</span>
            {samples.data.map((s) => (
              <button key={s} className="chip" onClick={() => trySample(s)} disabled={!!busy}>{s.replace('.pdf', '')}</button>
            ))}
          </div>
        )}
      </section>

      {busy && <p className="muted thinking">Reading {busy} and extracting fields (about 8 seconds)…</p>}
      {error && <Notice notice={{ kind: 'error', title: 'Could not read the document', text: error }} onClose={() => setError(null)} />}

      {result && (
        <div className="upload-grid">
          <ReviewForm key={version} result={result} onSaved={() => {}} />
          <aside className="card section">
            <h2 className="aside-h">Checks</h2>
            <Checks checks={result.checks} />
            <p className="muted small">{result.pages} page(s) · extracted in {result.seconds}s</p>
            <details className="raw">
              <summary>Text read from the PDF</summary>
              <pre>{result.raw_text}</pre>
            </details>
          </aside>
        </div>
      )}
    </>
  )
}
