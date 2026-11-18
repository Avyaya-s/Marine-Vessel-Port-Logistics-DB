// All calls to the FastAPI backend go through here.
// Paths are relative ("/api/..."); in development Vite proxies them to :8000.

async function request(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  const body = await res.json().catch(() => null)

  if (!res.ok) {
    // 400: the database rejected the change -> detail is its message.
    // 422: FastAPI input validation       -> detail is a list of problems.
    const detail = body?.detail
    const message = typeof detail === 'string'
      ? detail
      : detail?.[0]?.msg ?? `Request failed (HTTP ${res.status})`
    throw new Error(message)
  }
  return body
}

export const get = (path) => request(path)
export const post = (path, data) =>
  request(path, { method: 'POST', body: data === undefined ? undefined : JSON.stringify(data) })
