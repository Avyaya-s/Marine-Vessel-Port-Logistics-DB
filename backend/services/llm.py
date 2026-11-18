"""Calls to the local LLM server (Ollama), shared by the NLP features.

chat()  : chat completion; pass `schema` to force JSON matching a JSON Schema
embed() : text -> vector, for similarity search (HS code suggestion)
"""

import json
import os
import urllib.error
import urllib.request

# 127.0.0.1, not "localhost": on Windows "localhost" tries IPv6 (::1) first,
# Ollama listens on IPv4 only, and every call waits ~2 s for the fallback.
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen2.5:7b")
EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")


def _post(path: str, payload: dict, timeout: int = 180) -> dict:
    req = urllib.request.Request(f"{OLLAMA_URL}{path}", data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read())
    except urllib.error.URLError as e:
        raise RuntimeError(f"Cannot reach Ollama at {OLLAMA_URL}. Is it running? ({e.reason})") from e


def chat(messages: list[dict], schema: dict | None = None) -> str:
    payload = {
        "model": OLLAMA_MODEL,
        "messages": messages,
        "stream": False,
        "keep_alive": "30m",                              # keep the model in GPU memory between calls
        "options": {"temperature": 0, "num_ctx": 8192},   # temperature 0 = same answer every time
    }
    if schema:
        payload["format"] = schema                        # structured output: reply is JSON of this shape
    return _post("/api/chat", payload)["message"]["content"]


def embed(texts: list[str]) -> list[list[float]]:
    return _post("/api/embed", {"model": EMBED_MODEL, "input": texts, "keep_alive": "30m"})["embeddings"]
