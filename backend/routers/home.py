"""Role home screens: each stakeholder reads its own external view.

  operations -> v_berth_queue   (ships that need a berth / are waiting)
  agent      -> v_agent_calls   (own ships' progress, manifests, customs)
Customs' home uses v_customs_workload (routers/customs.py); the admin keeps
the port-wide dashboard.
"""

from fastapi import APIRouter, Depends

from auth import require
from db import fetch_all
from routers.port_calls import agent_company

router = APIRouter(prefix="/api/home", tags=["role home screens"])


@router.get("/operations/queue")
def berth_queue(user: dict = Depends(require("admin", "operations"))):
    """Calls not yet berthed, in the order the ships will be ready."""
    return fetch_all("SELECT * FROM v_berth_queue")


@router.get("/agent/calls")
def agent_calls(user: dict = Depends(require("admin", "agent"))):
    """The agent's own port calls with progress, manifests and customs status
    (admin sees every agent's calls)."""
    return fetch_all("""
        SELECT * FROM v_agent_calls
        WHERE (%(co)s::int IS NULL OR agent_id = %(co)s::int)
        ORDER BY (call_status = 'Departed'), eta
    """, {"co": agent_company(user)})
