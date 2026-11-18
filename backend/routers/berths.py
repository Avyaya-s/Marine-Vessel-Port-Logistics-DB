from fastapi import APIRouter

from db import fetch_all

router = APIRouter(prefix="/api", tags=["berths"])


@router.get("/berths")
def berth_occupancy():
    """One row per berth: who is alongside now and who is next (v_berth_occupancy)."""
    return fetch_all("SELECT * FROM v_berth_occupancy ORDER BY berth_number")


@router.get("/waiting-times")
def waiting_times():
    """Waiting time, berthing delay and ETA errors per arrived call (v_waiting_time)."""
    return fetch_all("SELECT * FROM v_waiting_time ORDER BY ata")
