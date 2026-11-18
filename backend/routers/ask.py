from fastapi import APIRouter
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from services import nl_query

router = APIRouter(prefix="/api/ask", tags=["NL assistant"])


class AskRequest(BaseModel):
    question: str = Field(min_length=3, max_length=500)


@router.post("")
async def ask(body: AskRequest):
    """Plain-English question -> SQL (local LLM) -> rows (read-only role).
    Always 200: `ok` says whether it worked; `sql` is shown either way."""
    # the LLM call blocks for a second or more; run it off the event loop
    return await run_in_threadpool(nl_query.ask, body.question.strip())


@router.get("/info")
def info():
    """Which model answers questions (shown on the Ask page)."""
    return {"model": nl_query.OLLAMA_MODEL, "max_rows": nl_query.MAX_ROWS}
