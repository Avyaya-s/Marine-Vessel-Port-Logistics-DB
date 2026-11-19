from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from auth import STAFF, require
from services import nl_query

router = APIRouter(prefix="/api/ask", tags=["NL assistant"])


class AskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=500)


@router.post("")
async def ask(body: AskRequest, user: dict = Depends(require(*STAFF))):
    """Plain-English question -> SQL (local LLM) -> rows (read-only role).
    Port staff only: generated SQL can read every table, so it would bypass
    the per-agent filtering of the other endpoints.
    Always 200: `ok` says whether it worked; `sql` is shown either way."""
    # the LLM call blocks for a second or more; run it off the event loop
    return await run_in_threadpool(nl_query.ask, body.question.strip())


@router.get("/info")
def info(user: dict = Depends(require(*STAFF))):
    """Which model answers questions (shown on the Ask page)."""
    return {"model": nl_query.OLLAMA_MODEL, "max_rows": nl_query.MAX_ROWS}
