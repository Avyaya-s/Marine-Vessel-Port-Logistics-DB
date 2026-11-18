"""FastAPI backend: the bridge between the React frontend and PostgreSQL.

Run (from the backend folder, with the virtual environment active):
    uvicorn main:app --reload
Interactive API docs: http://127.0.0.1:8000/docs
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from db import fetch_all, pool
from routers import berths, customs, port_calls


@asynccontextmanager
async def lifespan(app: FastAPI):
    pool.open()      # open DB connections when the server starts
    yield
    pool.close()     # and close them when it stops


app = FastAPI(title="Port Logistics API", lifespan=lifespan)

# The React dev server runs on another port (5173), which browsers treat as a
# different site.  CORS tells the browser it may call this API from there.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(port_calls.router)
app.include_router(berths.router)
app.include_router(customs.router)


@app.get("/api/health")
def health():
    """Quick check that the API is up and can reach the database."""
    fetch_all("SELECT 1")
    return {"status": "ok"}
