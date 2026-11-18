import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// In development the page is served by Vite on :5173 and the API runs on :8000.
// The proxy forwards every /api/... request to the backend, so the browser only
// ever talks to one address (no CORS problems, no hard-coded API URL).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://127.0.0.1:8000',
    },
  },
})
