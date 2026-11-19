"""Create login accounts in backend/users.json (run from the backend folder).

    .venv\\Scripts\\python manage_users.py demo
        creates the demo accounts below (overwrites users.json)
    .venv\\Scripts\\python manage_users.py add <username> <role> "<full name>" [company_id]
        adds or replaces one user; asks for the password
    .venv\\Scripts\\python manage_users.py list

Roles: admin, operations, customs, agent.  Agents need the company_id of
their agent company (see the company table: 1-3 in the sample data).
"""

import getpass
import json
import sys

from auth import ROLES, USERS_FILE, hash_password, load_users

DEMO = [  # username, role, name, company_id, password  (demo only, never in production)
    ("admin",     "admin",      "Harbour Master",             None, "admin123"),
    ("ops",       "operations", "Port Operations Officer",    None, "ops123"),
    ("customs",   "customs",    "A. Khan",                    None, "customs123"),
    ("seaways",   "agent",      "Seaways Shipping Agency",    1,    "agent123"),
    ("bluewater", "agent",      "Bluewater Maritime Agents",  2,    "agent123"),
]


def save(users: dict):
    USERS_FILE.write_text(json.dumps(users, indent=2), encoding="utf-8")


def user_entry(role, name, company_id, password):
    if role not in ROLES:
        sys.exit(f"Unknown role {role!r}; use one of {', '.join(ROLES)}.")
    if role == "agent" and company_id is None:
        sys.exit("An agent user needs the company_id of their agent company.")
    return {"name": name, "role": role, "company_id": company_id,
            "password_hash": hash_password(password), "active": True}


def main(args):
    if not args or args[0] == "list":
        for u, d in load_users().items():
            print(f"{u:12} {d['role']:11} {d['name']}" + (f"  (company {d['company_id']})" if d.get("company_id") else ""))
        return
    if args[0] == "demo":
        save({u: user_entry(r, n, c, p) for u, r, n, c, p in DEMO})
        print(f"Wrote {len(DEMO)} demo users to {USERS_FILE.name}:")
        for u, r, _, _, p in DEMO:
            print(f"  {u:10} / {p:11} ({r})")
        return
    if args[0] == "add" and len(args) in (4, 5):
        _, username, role, name, *rest = args
        company_id = int(rest[0]) if rest else None
        password = getpass.getpass(f"Password for {username}: ")
        users = load_users()
        users[username] = user_entry(role, name, company_id, password)
        save(users)
        print(f"Saved {username} ({role}).")
        return
    print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
