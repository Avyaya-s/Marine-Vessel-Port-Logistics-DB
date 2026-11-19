from fastapi import APIRouter, Depends

from auth import ANY, require
from db import fetch_all
from routers.port_calls import OWN_CALLS, agent_company

router = APIRouter(prefix="/api", tags=["berths"])


@router.get("/berths")
def berth_occupancy(user: dict = Depends(require(*ANY))):
    """One row per berth: who is alongside now and who is next (v_berth_occupancy).
    Shown to everyone: agents need to see which berths are busy."""
    return fetch_all("SELECT * FROM v_berth_occupancy ORDER BY berth_number")


@router.get("/waiting-times")
def waiting_times(user: dict = Depends(require(*ANY))):
    """Waiting time, berthing delay and ETA errors per arrived call (agents: own calls)."""
    return fetch_all(f"""
        SELECT w.* FROM v_waiting_time w
        JOIN port_call pc ON pc.call_id = w.call_id
        WHERE {OWN_CALLS}
        ORDER BY w.ata
    """, {"co": agent_company(user)})
