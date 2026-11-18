// Chart building blocks, drawn with plain HTML/CSS (no chart library).
// Every mark has a hover/focus tooltip; colour is never the only cue
// (legends, direct labels and a table view carry identity too).

import { useState } from 'react'
import { fmtDuration, fmtTime } from './format.js'

export const STATUS_ORDER = ['Expected', 'Waiting', 'Berthed', 'Departed']
const statusClass = (s) => `s-${s.toLowerCase()}`

// ---------------------------------------------------------------- tooltip
// One tooltip per chart.  Marks call show() on hover/focus and hide() on leave.
export function useTooltip() {
  const [tip, setTip] = useState(null)
  const show = (e, content) => {
    const r = e.currentTarget.getBoundingClientRect()
    const x = e.clientX ?? r.left + r.width / 2
    const y = e.clientY ?? r.top
    setTip({ x, y, content })
  }
  const hide = () => setTip(null)
  const markProps = (content, label) => ({
    tabIndex: 0,
    'aria-label': label,
    onMouseMove: (e) => show(e, content),
    onFocus: (e) => show(e, content),
    onMouseLeave: hide,
    onBlur: hide,
  })
  const node = tip && (
    <div className="tooltip" role="tooltip" style={{ left: tip.x + 14, top: tip.y + 14 }}>
      {tip.content}
    </div>
  )
  return { markProps, node }
}

export function Legend({ items }) {
  return (
    <div className="legend">
      {items.map((s) => (
        <span key={s} className="legend-item"><span className={`swatch ${statusClass(s)}`} />{s}</span>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------- berth timeline
// One row per berth, one bar per booking (planned berth_start -> berth_end).
// Bars on a row can never overlap: the check_berth_overlap trigger forbids it.
const DAY = 24 * 3600 * 1000

export function BerthTimeline({ berths, calls }) {
  const { markProps, node } = useTooltip()
  const bookings = calls.filter((c) => c.berth_number && c.berth_start)
  if (bookings.length === 0) return <p className="on-dark-muted">No berth bookings yet.</p>

  const starts = bookings.map((c) => +new Date(c.berth_start))
  const ends = bookings.map((c) => (c.berth_end ? +new Date(c.berth_end) : +new Date(c.berth_start) + DAY))
  // round the range out to whole days in IST (UTC+5:30)
  const IST = 5.5 * 3600 * 1000
  const from = Math.floor((Math.min(...starts) + IST) / DAY) * DAY - IST
  const to = Math.ceil((Math.max(...ends) + IST) / DAY) * DAY - IST
  const span = to - from
  const pct = (t) => ((t - from) / span) * 100

  const days = []
  for (let t = from; t <= to; t += DAY) days.push(t)
  const dayLabel = (t) => new Intl.DateTimeFormat('en-IN', { timeZone: 'Asia/Kolkata', day: '2-digit', month: 'short' }).format(t)
  const labelEvery = Math.ceil(days.length / 10)

  return (
    <div className="timeline">
      <div className="tl-axis">
        <div className="tl-label" />
        <div className="tl-track">
          {days.map((t, i) => i % labelEvery === 0 && (
            <span key={t} className="tl-tick" style={{ left: `${pct(t)}%` }}>{dayLabel(t)}</span>
          ))}
        </div>
      </div>
      {berths.map((b) => (
        <div key={b.berth_number} className="tl-row">
          <div className="tl-label">
            <strong>{b.berth_number}</strong>
            <span>{b.cargo_type}</span>
          </div>
          <div className="tl-track">
            {days.map((t) => <span key={t} className="tl-grid" style={{ left: `${pct(t)}%` }} />)}
            {bookings.filter((c) => c.berth_number === b.berth_number).map((c) => {
              const s = +new Date(c.berth_start)
              const open = !c.berth_end
              const e = open ? to : +new Date(c.berth_end)
              const width = Math.max(pct(e) - pct(s), 1.5)
              const tip = (
                <>
                  <strong>{c.vessel_name}</strong> · call {c.call_id}
                  <div>{c.call_status} · berth {c.berth_number}</div>
                  <div>{fmtTime(c.berth_start)} → {open ? 'open-ended' : fmtTime(c.berth_end)}</div>
                </>
              )
              return (
                <div key={c.call_id}
                     className={`tl-bar ${statusClass(c.call_status)}${open ? ' tl-open' : ''}`}
                     style={{ left: `${pct(s)}%`, width: `${width}%` }}
                     {...markProps(tip, `${c.vessel_name}, ${c.call_status}, berth ${c.berth_number}, ${fmtTime(c.berth_start)} to ${open ? 'open-ended' : fmtTime(c.berth_end)}`)}>
                  {width > 9 && <span className="tl-bar-label">{c.vessel_name}</span>}
                </div>
              )
            })}
          </div>
        </div>
      ))}
      {node}
    </div>
  )
}

// ---------------------------------------------------------------- segmented bar
// One whole (all port calls) split by status.  Parts at zero draw nothing.
// thin: no text on the bar and no legend, for use above a list that already
// names each part with its figure (the list's swatches replace the legend).
export function SegmentedBar({ counts, thin = false }) {
  const { markProps, node } = useTooltip()
  const total = STATUS_ORDER.reduce((n, s) => n + (counts[s] ?? 0), 0)
  if (!total) return <p className="muted">No port calls.</p>
  return (
    <div>
      <div className={`seg-bar${thin ? ' seg-thin' : ''}`} role="img" aria-label={STATUS_ORDER.map((s) => `${s} ${counts[s] ?? 0}`).join(', ')}>
        {STATUS_ORDER.filter((s) => counts[s]).map((s) => {
          const share = Math.round((counts[s] / total) * 100)
          return (
            <div key={s} className={`seg ${statusClass(s)}`} style={{ flexGrow: counts[s] }}
                 {...markProps(<><strong>{s}</strong><div>{counts[s]} of {total} calls · {share}%</div></>, `${s}: ${counts[s]} of ${total}`)}>
              {!thin && share >= 12 && <span className="seg-label">{counts[s]}</span>}
            </div>
          )
        })}
      </div>
      {!thin && <Legend items={STATUS_ORDER.filter((s) => counts[s])} />}
      {node}
    </div>
  )
}

// ---------------------------------------------------------------- ranked bars
// Anchorage waiting time per vessel, longest first, one hue.
export function RankedBars({ rows }) {
  const { markProps, node } = useTooltip()
  const done = rows.filter((r) => r.waiting_time !== null).sort((a, b) => b.waiting_time - a.waiting_time)
  const waiting = rows.filter((r) => r.waiting_time === null)
  const max = Math.max(...done.map((r) => r.waiting_time), 1)
  return (
    <div className="ranked">
      {done.map((r) => (
        <div key={r.call_id} className="ranked-row">
          <span className="ranked-name">{r.vessel_name}</span>
          <div className="ranked-track">
            <div className="ranked-bar" style={{ width: `${(r.waiting_time / max) * 100}%` }}
                 {...markProps(<><strong>{r.vessel_name}</strong><div>Arrived {fmtTime(r.ata)}</div><div>Berthed {fmtTime(r.atb)}</div><div>Waited {fmtDuration(r.waiting_time)}</div></>,
                               `${r.vessel_name} waited ${fmtDuration(r.waiting_time)}`)} />
          </div>
          <span className="ranked-value">{fmtDuration(r.waiting_time)}</span>
        </div>
      ))}
      {waiting.map((r) => (
        <div key={r.call_id} className="ranked-row">
          <span className="ranked-name">{r.vessel_name}</span>
          <span className="muted small ranked-note">still at anchor since {fmtTime(r.ata)}</span>
        </div>
      ))}
      {node}
    </div>
  )
}

// ---------------------------------------------------------------- meter list
// Risk score (0-1) per pending filing.  Severity = colour + icon + word.
export function riskLevel(score) {
  if (score === null || score === undefined) return null
  if (score >= 0.7) return { key: 'critical', word: 'High', icon: '▲' }
  if (score >= 0.3) return { key: 'warning', word: 'Medium', icon: '●' }
  return { key: 'good', word: 'Low', icon: '✓' }
}

export function MeterList({ rows }) {
  if (rows.length === 0) return <p className="muted">Nothing pending.</p>
  return (
    <div className="meters">
      {rows.map((f) => {
        const lvl = riskLevel(f.risk_score)
        return (
          <div key={f.filing_no} className="meter-row">
            <div className="meter-head">
              <span><strong>{f.filing_no}</strong> <span className="muted small">{f.cargo_description}</span></span>
              <span className="meter-figure">
                {lvl ? <><span className={`sev-icon sev-${lvl.key}`} aria-hidden="true">{lvl.icon}</span>{lvl.word} {f.risk_score.toFixed(2)}</>
                     : <span className="muted">not scored</span>}
              </span>
            </div>
            <div className={`meter-track ${lvl ? `track-${lvl.key}` : ''}`}>
              {lvl && <div className={`meter-fill fill-${lvl.key}`} style={{ width: `${f.risk_score * 100}%` }} />}
            </div>
          </div>
        )
      })}
    </div>
  )
}
