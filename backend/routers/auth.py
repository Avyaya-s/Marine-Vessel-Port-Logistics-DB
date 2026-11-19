from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from auth import check_login, current_user, make_token

router = APIRouter(prefix="/api/auth", tags=["auth"])


class LoginRequest(BaseModel):
    username: str
    password: str


@router.post("/login")
def login(body: LoginRequest):
    user = check_login(body.username.strip(), body.password)
    if not user:
        # same message for "no such user" and "wrong password": don't reveal which
        raise HTTPException(401, "Wrong username or password.")
    return {"token": make_token(user), "user": user}


@router.get("/me")
def me(user: dict = Depends(current_user)):
    return user
