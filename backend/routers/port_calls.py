from fastapi import APIRouter, Depends

from auth import ANY, require
from db import fetch_all, fetch_one

router = APIRouter(prefix="/api/port-calls", tags=["port calls"])


def agent_company(user: dict) -> int | None:
    """The agent's company id (to filter by), or None for port staff (see all)."""
    return user["company_id"] if user["role"] == "agent" else None


# "(%(co)s IS NULL OR pc.agent_id = %(co)s)" keeps every row for staff and only
# the agent's own calls for an agent.  The id is a query parameter, never
# pasted into the SQL text.
OWN_CALLS = "(%(co)s::int IS NULL OR pc.agent_id = %(co)s::int)"


@router.get("")
def list_port_calls(user: dict = Depends(require(*ANY))):
    """Port calls with vessel, agent and berth details (agents: only their own)."""
    return fetch_all(f"""
        SELECT pc.call_id, pc.call_status,
               v.vessel_name, v.vessel_type, v.loa, v.draft,
               c.company_name AS agent,
               pc.berth_number, pc.berth_start, pc.berth_end,
               pc.eta, pc.predicted_eta, pc.ata, pc.atb, pc.atd
        FROM port_call pc
        JOIN vessel  v ON v.imo_number = pc.imo_number
        JOIN company c ON c.company_id = pc.agent_id
        WHERE {OWN_CALLS}
        ORDER BY pc.eta
    """, {"co": agent_company(user)})


@router.get("/summary")
def status_summary(user: dict = Depends(require(*ANY))):
    """How many calls are in each status (agents: only their own)."""
    rows = fetch_all(f"SELECT call_status, count(*) AS n FROM port_call pc WHERE {OWN_CALLS} GROUP BY call_status",
                     {"co": agent_company(user)})
    counts = {status: 0 for status in ("Expected", "Waiting", "Berthed", "Departed")}
    counts.update({r["call_status"]: r["n"] for r in rows})
    return counts


@router.post("/{call_id}/allocate")
def allocate_berth(call_id: int, user: dict = Depends(require("admin", "operations"))):
    """Run the allocate_berth() stored procedure for one call (port staff only)."""
    row = fetch_one("CALL allocate_berth(%s)", (call_id,))
    return {"call_id": call_id, "berth": row["o_berth"],
            "berth_start": row["o_start"], "berth_end": row["o_end"]}
