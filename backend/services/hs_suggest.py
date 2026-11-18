"""HS code suggestion by semantic search.

The reference list (data/hs_codes.csv: 6-digit HS code + plain description)
is embedded once with nomic-embed-text.  A cargo description is embedded the
same way, and the closest reference descriptions by cosine similarity are the
suggestions.  Embeddings compare meaning, not exact words, so
"spanners and wrenches" finds "Adjustable hand spanners".

The model only ranks codes that exist in the list, so it cannot invent an HS
code (unlike asking a chat model to "give me the HS code").
"""

import csv
import math
from pathlib import Path

from services.llm import embed

HS_FILE = Path(__file__).resolve().parents[2] / "data" / "hs_codes.csv"

_codes: list[dict] | None = None
_vectors: list[list[float]] | None = None


def _load():
    global _codes, _vectors
    if _codes is None:
        with open(HS_FILE, encoding="utf-8") as f:
            _codes = list(csv.DictReader(f))
        # nomic-embed-text expects task prefixes: documents vs queries
        _vectors = embed([f'search_document: {c["description"]}' for c in _codes])
    return _codes, _vectors


def _cosine(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    return dot / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)))


def suggest(description: str, k: int = 3) -> list[dict]:
    """Top-k HS codes for a cargo description, best first."""
    if not description or not description.strip():
        return []
    codes, vectors = _load()
    q = embed([f"search_query: {description}"])[0]
    scored = sorted(((_cosine(q, v), c) for v, c in zip(vectors, codes)), key=lambda t: t[0], reverse=True)
    return [{"hs_code": c["hs_code"], "description": c["description"], "score": round(s, 3)}
            for s, c in scored[:k]]


def describe(hs_code: str) -> str | None:
    """Reference description for a code's 6-digit heading, if it is in the list."""
    codes, _ = _load()
    six = (hs_code or "")[:6]
    return next((c["description"] for c in codes if c["hs_code"] == six), None)
