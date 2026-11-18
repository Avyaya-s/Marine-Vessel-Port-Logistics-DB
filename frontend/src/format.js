// Display helpers.  The API sends times as ISO strings with a UTC offset;
// we always show them in port local time (IST).

const timeFmt = new Intl.DateTimeFormat('en-IN', {
  timeZone: 'Asia/Kolkata',
  day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit', hour12: false,
})

export function fmtTime(iso) {
  return iso ? timeFmt.format(new Date(iso)) : '—'
}

// The API sends intervals (waiting time, delays) as a number of seconds.
export function fmtDuration(seconds) {
  if (seconds === null || seconds === undefined) return '—'
  const sign = seconds < 0 ? '−' : ''
  const mins = Math.round(Math.abs(seconds) / 60)
  const h = Math.floor(mins / 60)
  const m = mins % 60
  return h ? `${sign}${h}h ${m}m` : `${sign}${m}m`
}

const inr = new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', maximumFractionDigits: 0 })

export function fmtMoney(value) {
  return value === null || value === undefined ? '—' : inr.format(value)
}
