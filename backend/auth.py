"""Login and role checks (application level; no database table).

Users live in backend/users.json (git-ignored), created with manage_users.py:
    {"username": {"name": ..., "role": ..., "company_id": ..., "password_hash": ...}}

Flow
  1. POST /api/auth/login  -> password checked against the bcrypt hash
  2. the server returns a signed JWT (username, role, company_id, expiry)
  3. the browser sends it on every request:  Authorization: Bearer <token>
  4. each endpoint declares which roles may call it: Depends(require("admin", ...))

The token is signed with JWT_SECRET (HMAC-SHA256): anyone can read it, but
nobody can change the role inside it without the secret, because the
signature would no longer match.
"""

import json
import os
import secrets
import time
from pathlib import Path

import bcrypt
import jwt
from dotenv import load_dotenv
from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

USERS_FILE = Path(__file__).parent / "users.json"
TOKEN_HOURS = 8
ROLES = ("admin", "operations", "customs", "agent")

load_dotenv()

# Without JWT_SECRET in .env a random one is made at start-up: fine for
# development, but every restart then logs everybody out.
JWT_SECRET = os.environ.get("JWT_SECRET") or secrets.token_hex(32)

_bearer = HTTPBearer(auto_error=False)


def load_users() -> dict:
    if not USERS_FILE.exists():
        return {}
    return json.loads(USERS_FILE.read_text(encoding="utf-8"))


def hash_password(password: str) -> str:
    # bcrypt is deliberately slow and salted: the same password gives a
    # different hash every time, and guessing millions per second is impossible
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()


def check_login(username: str, password: str) -> dict | None:
    user = load_users().get(username)
    # always run bcrypt, even for an unknown user, so response time does not
    # reveal which usernames exist
    stored = user["password_hash"] if user else hash_password("dummy-password")
    ok = bcrypt.checkpw(password.encode(), stored.encode())
    if not (user and ok and user.get("active", True)):
        return None
    return {"username": username, "name": user["name"], "role": user["role"],
            "company_id": user.get("company_id")}


def make_token(user: dict) -> str:
    claims = {**user, "sub": user["username"], "exp": int(time.time()) + TOKEN_HOURS * 3600}
    return jwt.encode(claims, JWT_SECRET, algorithm="HS256")


def current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> dict:
    """FastAPI dependency: the logged-in user, or 401."""
    if creds is None:
        raise HTTPException(401, "Please log in.")
    try:
        claims = jwt.decode(creds.credentials, JWT_SECRET, algorithms=["HS256"])
    except jwt.ExpiredSignatureError:
        raise HTTPException(401, "Your session has expired. Please log in again.")
    except jwt.InvalidTokenError:
        raise HTTPException(401, "Invalid login token. Please log in again.")
    return {k: claims.get(k) for k in ("username", "name", "role", "company_id")}


def require(*roles: str):
    """Dependency factory: only these roles may call the endpoint (else 403)."""
    def check(user: dict = Depends(current_user)) -> dict:
        if user["role"] not in roles:
            raise HTTPException(403, f"Your role ({user['role']}) is not allowed to do this.")
        return user
    return check


# who may use what (the frontend mirrors this to show/hide pages)
ANY = ROLES
STAFF = ("admin", "operations", "customs")
