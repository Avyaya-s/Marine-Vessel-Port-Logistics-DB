"""Database access: one connection pool shared by every request.

Opening a PostgreSQL connection is slow (network handshake, login), so the
pool keeps a few connections open and lends one to each request.

Each `with pool.connection()` block is one transaction: it COMMITs when the
block ends normally and ROLLs BACK if an exception escapes it.
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


def fetch_all(sql: str, params: tuple = ()) -> list[dict]:
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
