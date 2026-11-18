import { useState } from 'react'
import { post } from '../api.js'
import { fmtTime } from '../format.js'
import { useFetch } from '../useFetch.js'

const EXAMPLES = [
  'Which ships are waiting at anchorage?',
  'What was the longest wait at anchorage?',
  'Which berths are free right now?',
  'List customs filings that are held, with their consignee',
  'How many containers of each size are there?',
  'Which vessels are longer than 250 metres?',
]

const ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/

function cell(v) {
  if (v === null || v === undefined) return <span className="muted">—</span>
  if (typeof v === 'string' && ISO.test(v)) return fmtTime(v)
  if (typeof v === 'number' && !Number.isInteger(v)) return v.toLocaleString('en-IN', { maximumFractionDigits: 2 })
  if (typeof v === 'number') return v.toLocaleString('en-IN')
  return String(v)
}

function Answer({ a }) {
  const [copied, setCopied] = useState(false)
  function copy() {
    navigator.clipboard?.writeText(a.sql).then(() => { setCopied(true); setTimeout(() => setCopied(false), 1500) })
  }
  return (
    <section className="card section answer">
      <div className="answer-q">“{a.question}”</div>

      {a.sql && (
        <div className="sql-box">
          <div className="sql-head">
            <span>Generated SQL{a.attempts > 1 && <span className="pill">self-corrected</span>}</span>
            <button className="btn-ghost" onClick={copy}>{copied ? 'Copied' : 'Copy'}</button>
          </div>
          <pre><code>{a.sql}</code></pre>
        </div>
      )}

      {a.ok ? (
        <>
          <div className="answer-meta muted small">
            {a.row_count} row{a.row_count === 1 ? '' : 's'}{a.truncated && ` (first ${a.row_count} shown)`} · {a.seconds}s · {a.model}
          </div>
          {a.row_count === 0 ? <p className="muted">The query ran but returned no rows.</p> : (
            <div className="answer-table">
              <table>
                <thead><tr>{a.columns.map((c, i) => <th key={i}>{c.replaceAll('_', ' ')}</th>)}</tr></thead>
                <tbody>
                  {a.rows.map((r, i) => <tr key={i}>{r.map((v, j) => <td key={j}>{cell(v)}</td>)}</tr>)}
                </tbody>
              </table>
            </div>
          )}
        </>
      ) : (
        <div className="notice notice-error" role="status">
          <span className="notice-icon" aria-hidden="true">!</span>
          <div className="notice-body"><strong>No answer</strong><p>{a.error}</p></div>
        </div>
      )}
    </section>
  )
}

export default function Ask() {
  const info = useFetch('/ask/info')
  const [question, setQuestion] = useState('')
  const [busy, setBusy] = useState(false)
  const [answers, setAnswers] = useState([])     // newest first, this session only

  async function ask(q) {
    const text = (q ?? question).trim()
    if (text.length < 3 || busy) return
    setQuestion(text)
    setBusy(true)
    try {
      const a = await post('/ask', { question: text })
      setAnswers((prev) => [a, ...prev].slice(0, 10))
    } catch (e) {
      setAnswers((prev) => [{ question: text, ok: false, error: e.message }, ...prev])
    } finally {
      setBusy(false)
    }
  }

  return (
    <>
      <section className="card section">
        <div className="section-head">
          <div>
            <h2>Ask the database</h2>
            <p className="muted small">
              Your question is turned into SQL by a local LLM ({info.data?.model ?? '…'}, running on this PC),
              checked, then run as the read-only <code>nl_assistant</code> user.
            </p>
          </div>
        </div>

        <form className="ask-form" onSubmit={(e) => { e.preventDefault(); ask() }}>
          <input className="ask-input" value={question} onChange={(e) => setQuestion(e.target.value)}
                 placeholder="e.g. Which ships waited more than 3 hours at anchorage?" maxLength={500}
                 aria-label="Your question" disabled={busy} />
          <button type="submit" disabled={busy || question.trim().length < 3}>{busy ? 'Thinking…' : 'Ask'}</button>
        </form>

        <div className="chips">
          {EXAMPLES.map((q) => (
            <button key={q} className="chip" onClick={() => ask(q)} disabled={busy}>{q}</button>
          ))}
        </div>

        <div className="safety small">
          <span>🔒 SELECT only</span><span>Read-only database role</span><span>5 s query timeout</span><span>Max 200 rows</span>
        </div>
      </section>

      {busy && <p className="muted thinking">Writing SQL for “{question}”…</p>}
      {answers.map((a, i) => <Answer key={answers.length - i} a={a} />)}
    </>
  )
}
