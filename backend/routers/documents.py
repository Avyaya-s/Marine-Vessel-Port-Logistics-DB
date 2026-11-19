from decimal import Decimal
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from auth import require
from routers.port_calls import agent_company
from services import documents, hs_suggest

router = APIRouter(prefix="/api/documents", tags=["documents"])

MAX_BYTES = 5 * 1024 * 1024
SAMPLES = Path(__file__).resolve().parents[2] / "data" / "sample_docs"
UPLOADERS = ("admin", "operations", "agent")


@router.post("/extract")
async def extract(file: UploadFile = File(...), user: dict = Depends(require(*UPLOADERS))):
    """Upload a Bill of Lading PDF; returns the extracted fields and checks.
    Nothing is saved yet."""
    data = await file.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        raise HTTPException(413, "File is larger than 5 MB.")
    try:
        return await run_in_threadpool(documents.extract, data, agent_company(user))
    except documents.DocumentError as e:
        raise HTTPException(422, str(e)) from e
    except RuntimeError as e:                       # Ollama not reachable
        raise HTTPException(503, str(e)) from e


@router.get("/hs-suggest")
def hs_suggestions(q: str, user: dict = Depends(require(*UPLOADERS))):
    """HS code suggestions for an edited cargo description."""
    return hs_suggest.suggest(q)


class ContainerIn(BaseModel):
    container_no: str
    iso_type: str
    seal_no: str = ""


class ShipmentIn(BaseModel):
    manifest_no: str
    shipment_no: str = Field(min_length=1, max_length=20)
    shipper_name: str = Field(min_length=1, max_length=150)
    consignee_name: str = Field(min_length=1, max_length=150)
    cargo_description: str = Field(min_length=1)
    origin_port: str
    hs_code: str
    cargo_quantity: int = Field(gt=0)
    gross_weight: Decimal = Field(gt=0)
    containers: list[ContainerIn] = []


@router.post("/confirm")
def confirm(body: ShipmentIn, user: dict = Depends(require(*UPLOADERS))):
    """Insert the confirmed shipment (one transaction)."""
    try:
        return documents.confirm(body.model_dump(), agent_company(user))
    except ValueError as e:
        raise HTTPException(400, str(e)) from e


@router.get("/samples")
def samples(user: dict = Depends(require(*UPLOADERS))):
    """Sample Bills of Lading for trying the feature."""
    return sorted(p.name for p in SAMPLES.glob("*.pdf"))


@router.get("/samples/{name}")
def sample(name: str, user: dict = Depends(require(*UPLOADERS))):
    # only names from the listing: no path tricks like ../../.env
    if name not in samples(user):
        raise HTTPException(404, "No such sample.")
    return FileResponse(SAMPLES / name, media_type="application/pdf")
