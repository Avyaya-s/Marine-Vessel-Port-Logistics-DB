// Who is logged in, and what their role may see.
//
// The token is kept in sessionStorage: it survives a page reload but is gone
// when the tab is closed.  The real permission checks happen in the backend
// (every endpoint checks the role); this file only hides what a role can't use.

import { createContext, useContext, useEffect, useState } from 'react'
import { post, setToken, setUnauthorizedHandler } from './api.js'

const KEY = 'port-logistics-session'
const AuthContext = createContext(null)

// Mirrors the backend's require(...) rules.
export const ROLE_LABEL = {
  admin: 'Administrator', operations: 'Port Operations', customs: 'Customs Officer', agent: 'Shipping Agent',
}
const PAGE_ROLES = {
  '/dashboard':  ['admin', 'operations', 'customs', 'agent'],
  '/port-calls': ['admin', 'operations', 'customs', 'agent'],
  '/customs':    ['admin', 'operations', 'customs'],
  '/ask':        ['admin', 'operations', 'customs'],
  '/upload':     ['admin', 'operations', 'agent'],
  '/map':        ['admin', 'operations', 'customs', 'agent'],
}
const ACTION_ROLES = {
  allocateBerth: ['admin', 'operations'],
  clearCustoms:  ['admin', 'customs'],
  seeCustoms:    ['admin', 'operations', 'customs'],
}

function readSession() {
  try { return JSON.parse(sessionStorage.getItem(KEY)) } catch { return null }
}

export function AuthProvider({ children }) {
  const [session, setSession] = useState(() => {
    const s = readSession()
    if (s) setToken(s.token)
    return s
  })

  function logout() {
    setToken(null)
    setSession(null)
    try { sessionStorage.removeItem(KEY) } catch { /* storage blocked */ }
  }

  async function login(username, password) {
    const s = await post('/auth/login', { username, password })
    setToken(s.token)
    setSession(s)
    try { sessionStorage.setItem(KEY, JSON.stringify(s)) } catch { /* storage blocked */ }
  }

  // any 401 from the API (expired or invalid token) logs the user out
  useEffect(() => { setUnauthorizedHandler(logout) }, [])

  const user = session?.user ?? null
  const value = {
    user,
    login,
    logout,
    canSee: (path) => !!user && (PAGE_ROLES[path] ?? []).includes(user.role),
    can: (action) => !!user && (ACTION_ROLES[action] ?? []).includes(user.role),
  }
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export const useAuth = () => useContext(AuthContext)
