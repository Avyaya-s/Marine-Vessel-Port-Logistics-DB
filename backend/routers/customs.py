from decimal import Decimal
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from auth import STAFF, require
from db import fetch_all, fetch_one

router = APIRouter(prefix="/api/customs", tags=["customs"])


class ClearRequest(BaseModel):
    # Decimal, not float: money must be exact (0.1 + 0.2 != 0.3 in floats).
    duty: Decimal = Field(ge=0, description="Duty assessed, in INR")


class InspectionRequest(BaseModel):
    result: Literal["Pending", "Clear", "Discrepancy"]
    remarks: str = Field(default="", max_length=500)


@router.get("/pending")
def pending_customs(user: dict = Depends(require(*STAFF))):
    """Uncleared filings, riskiest first (v_pending_customs)."""
    return fetch_all("SELECT * FROM v_pending_customs")


@router.get("/workload")
def workload(user: dict = Depends(require(*STAFF))):
    """One row of counts for the customs officer's home screen (v_customs_workload)."""
    return fetch_all("SELECT * FROM v_customs_workload")[0]


@router.get("/{filing_no}")
def filing_detail(filing_no: str, user: dict = Depends(require(*STAFF))):
    """Everything an officer needs to decide on one filing."""
    rows = fetch_all("""
        SELECT cf.*, s.cargo_description, s.hs_code, s.origin_port, s.cargo_quantity, s.gross_weight,
               sh.company_name AS shipper, co.company_name AS consignee, co.iec_code,
               v.vessel_name, pc.call_id, m.manifest_no
        FROM customs_filing cf
        JOIN shipment s           ON s.shipment_no = cf.shipment_no
        JOIN company sh           ON sh.company_id = s.shipper_id
        JOIN company co           ON co.company_id = s.consignee_id
        JOIN shipping_manifest m  ON m.manifest_no = s.manifest_no
        JOIN port_call pc         ON pc.call_id = m.call_id
        JOIN vessel v             ON v.imo_number = pc.imo_number
        WHERE cf.filing_no = %s
    """, (filing_no,))
    if not rows:
        raise HTTPException(404, f"Filing {filing_no} not found.")
    detail = rows[0]
    detail["containers"] = fetch_all("""
        SELECT sc.container_no, c.iso_type, c.size, sc.seal_no, sc.container_status
        FROM shipment_container sc JOIN container c ON c.container_no = sc.container_no
        WHERE sc.shipment_no = %s ORDER BY sc.container_no
    """, (detail["shipment_no"],))
    detail["inspections"] = fetch_all(
        "SELECT * FROM inspection WHERE filing_no = %s ORDER BY inspection_no", (filing_no,))
    return detail


@router.post("/{filing_no}/inspections")
def record_inspection(filing_no: str, body: InspectionRequest, user: dict = Depends(require("admin", "customs"))):
    """Record an inspection (record_inspection() procedure: numbers it, inserts it
    and updates the filing status in one transaction).  The officer's name comes
    from the login token, not from the request."""
    row = fetch_one("CALL record_inspection(%s, %s, %s, %s)",
                    (filing_no, user["name"], body.result, body.remarks or None))
    return {"filing_no": filing_no, "inspection_no": row["o_inspection_no"], "filing_status": row["o_filing_status"]}


@router.post("/{filing_no}/clear")
def clear_customs(filing_no: str, body: ClearRequest, user: dict = Depends(require("admin", "customs"))):
    """Run the clear_customs() transaction.  All-or-nothing: on any error the
    database rolls everything back and the error message is returned (400)."""
    # ::numeric makes the type explicit so PostgreSQL finds the procedure
    # clear_customs(varchar, numeric) and not a (non-existent) float version.
    row = fetch_one("CALL clear_customs(%s, %s::numeric)", (filing_no, body.duty))
    return {"filing_no": filing_no, "containers_released": row["o_released"]}
