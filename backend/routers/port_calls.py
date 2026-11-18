from fastapi import APIRouter

from db import fetch_all, fetch_one

router = APIRouter(prefix="/api/port-calls", tags=["port calls"])


@router.get("")
def list_port_calls():
    """Every port call with vessel, agent and berth details."""
    return fetch_all("""
        SELECT pc.call_id, pc.call_status,
               v.vessel_name, v.vessel_type, v.loa, v.draft,
               c.company_name AS agent,
               pc.berth_number, pc.berth_start, pc.berth_end,
               pc.eta, pc.predicted_eta, pc.ata, pc.atb, pc.atd
        FROM port_call pc
        JOIN vessel  v ON v.imo_number = pc.imo_number
        JOIN company c ON c.company_id = pc.agent_id
        ORDER BY pc.eta
    """)


@router.get("/summary")
def status_summary():
    """How many calls are in each status (for the dashboard cards)."""
    rows = fetch_all("SELECT call_status, count(*) AS n FROM port_call GROUP BY call_status")
    counts = {status: 0 for status in ("Expected", "Waiting", "Berthed", "Departed")}
    counts.update({r["call_status"]: r["n"] for r in rows})
    return counts


@router.post("/{call_id}/allocate")
def allocate_berth(call_id: int):
    """Run the allocate_berth() stored procedure for one call."""
    row = fetch_one("CALL allocate_berth(%s)", (call_id,))
    return {"call_id": call_id, "berth": row["o_berth"],
            "berth_start": row["o_start"], "berth_end": row["o_end"]}
