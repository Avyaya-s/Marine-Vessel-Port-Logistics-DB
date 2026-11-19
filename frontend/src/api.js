// All calls to the FastAPI backend go through here.
// Paths are relative ("/api/..."); in development Vite proxies them to :8000.
// The login token (set by auth.jsx) is attached to every request.

let token = null
let onUnauthorized = () => {}

export function setToken(t) { token = t }
export function setUnauthorizedHandler(fn) { onUnauthorized = fn }
export function authHeaders() { return token ? { Authorization: `Bearer ${token}` } : {} }

async function request(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    ...options,
    headers: { 'Content-Type': 'application/json', ...authHeaders(), ...options.headers },
  })
  const body = await res.json().catch(() => null)

  if (!res.ok) {
    // 400: the database rejected the change -> detail is its message.
    // 401: not logged in / session expired   -> log out.
    // 403: logged in, but the role may not do this.
    // 422: FastAPI input validation          -> detail is a list of problems.
    const detail = body?.detail
    const message = typeof detail === 'string'
      ? detail
      : detail?.[0]?.msg ?? `Request failed (HTTP ${res.status})`
    if (res.status === 401 && path !== '/auth/login') onUnauthorized()
    throw new Error(message)
  }
  return body
}

export const get = (path) => request(path)
export const post = (path, data) =>
  request(path, { method: 'POST', body: data === undefined ? undefined : JSON.stringify(data) })
