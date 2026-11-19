"""Database access: connection pools shared by every request.

Opening a PostgreSQL connection is slow (network handshake, login), so a
pool keeps a few connections open and lends one to each request.

Each `with pool.connection()` block is one transaction: it COMMITs when the
block ends normally and ROLLs BACK if an exception escapes it.

Two pools, two database users:
  pool       DATABASE_URL     the app's normal user (runs views and procedures)
  nl_pool()  NL_DATABASE_URL  the read-only nl_assistant role, used ONLY for
                              SQL written by the LLM.  There is deliberately no
                              fallback to DATABASE_URL: LLM-generated SQL must
                              never run with write permissions.
"""

import os

from dotenv import load_dotenv
from fastapi import HTTPException
from psycopg import Error as PgError
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

load_dotenv()

DATABASE_URL = os.environ.get("DATABASE_URL")
if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is not set. Copy backend/.env.example to backend/.env.")

pool = ConnectionPool(
    DATABASE_URL,
    min_size=1,
    max_size=5,
    kwargs={"row_factory": dict_row},  # rows come back as {"column": value}
    open=False,
)

_nl_pool: ConnectionPool | None = None


def nl_pool() -> ConnectionPool:
    """Pool for the read-only nl_assistant role (created on first use)."""
    global _nl_pool
    if _nl_pool is None:
        url = os.environ.get("NL_DATABASE_URL")
        if not url:
            raise RuntimeError("NL_DATABASE_URL is not set in backend/.env "
                               "(the read-only nl_assistant login).")
        _nl_pool = ConnectionPool(url, min_size=1, max_size=3, open=True)
    return _nl_pool


def close_pools() -> None:
    pool.close()
    if _nl_pool is not None:
        _nl_pool.close()


def fetch_all(sql: str, params: tuple | dict = ()) -> list[dict]:
    """Run a SELECT and return every row as a dict."""
    with pool.connection() as conn:
        return conn.execute(sql, params).fetchall()


def fetch_one(sql: str, params: tuple = ()) -> dict | None:
    """Run a statement (e.g. CALL ...) and return its first row, if any."""
    try:
        with pool.connection() as conn:
            return conn.execute(sql, params).fetchone()
    except PgError as e:
        # A trigger, CHECK or procedure rejected the change.  The transaction
        # has already been rolled back; pass the database's own message on.
        message = e.diag.message_primary or str(e)
        raise HTTPException(status_code=400, detail=message) from e
