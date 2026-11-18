import { useCallback, useEffect, useState } from 'react'
import { get } from './api.js'

// Loads `path` when the component appears.  `reload()` fetches it again,
// e.g. after a button changes data in the database.
export function useFetch(path) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(true)

  const reload = useCallback(() => {
    setLoading(true)
    get(path)
      .then((d) => { setData(d); setError(null) })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false))
  }, [path])

  useEffect(reload, [reload])

  return { data, error, loading, reload }
}
