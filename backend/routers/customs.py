from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from auth import STAFF, require
from db import fetch_all, fetch_one

router = APIRouter(prefix="/api/customs", tags=["customs"])


class ClearRequest(BaseModel):
    # Decimal, not float: money must be exact (0.1 + 0.2 != 0.3 in floats).
    duty: Decimal = Field(ge=0, description="Duty assessed, in INR")


@router.get("/pending")
def pending_customs(user: dict = Depends(require(*STAFF))):
    """Uncleared filings, riskiest first (v_pending_customs)."""
    return fetch_all("SELECT * FROM v_pending_customs")


@router.post("/{filing_no}/clear")
def clear_customs(filing_no: str, body: ClearRequest, user: dict = Depends(require("admin", "customs"))):
    """Run the clear_customs() transaction.  All-or-nothing: on any error the
    database rolls everything back and the error message is returned (400)."""
    # ::numeric makes the type explicit so PostgreSQL finds the procedure
    # clear_customs(varchar, numeric) and not a (non-existent) float version.
    row = fetch_one("CALL clear_customs(%s, %s::numeric)", (filing_no, body.duty))
    return {"filing_no": filing_no, "containers_released": row["o_released"]}
