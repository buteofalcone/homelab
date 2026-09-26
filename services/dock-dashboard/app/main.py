from __future__ import annotations

import asyncio
import json
import os
import secrets
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from fastapi import Cookie, FastAPI, Header, HTTPException, Request, Response
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field


APP_DIR = Path(__file__).resolve().parent
STATIC_DIR = APP_DIR / "static"
STATUS_FILE = Path(os.getenv("DASHBOARD_STATUS_FILE", "/run/hp-dashboard/status.json"))
ACTION_HELPER = os.getenv("DASHBOARD_ACTION_HELPER", "/usr/local/libexec/hp-dashboard-action")
USERNAME = os.getenv("DASHBOARD_USERNAME", "butenko")
PASSWORD_HASH = os.getenv("DASHBOARD_PASSWORD_HASH", "")
PROXY_TOKEN = os.getenv("DASHBOARD_PROXY_TOKEN", "")
DASHBOARD_HOST = os.getenv("DASHBOARD_HOST", "dashboard.butenko.online")
SESSION_IDLE_SECONDS = int(os.getenv("DASHBOARD_SESSION_IDLE_SECONDS", "1800"))
SESSION_MAX_SECONDS = int(os.getenv("DASHBOARD_SESSION_MAX_SECONDS", "28800"))
COOKIE_NAME = "hp_dashboard_session"
LOGIN_WINDOW_SECONDS = 900
LOGIN_MAX_FAILURES = 5

CATALOG_FILE = Path(os.getenv("DASHBOARD_CATALOG_FILE", "/etc/homelab/dashboard-service-catalog.json"))


def load_action_catalog() -> list[dict[str, str]]:
    candidates = [CATALOG_FILE, Path("/opt/homelab/config/service-catalog.json"), APP_DIR.parents[2] / "config" / "service-catalog.json"]
    for candidate in candidates:
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        targets = []
        for application in payload.get("applications", []):
            if isinstance(application, dict) and isinstance(application.get("restart"), list) and application.get("restart"):
                target = application.get("id")
                label = application.get("label")
                if isinstance(target, str) and isinstance(label, str):
                    targets.append({"id": target, "label": label})
        return targets
    return []


RESTART_CATALOG = load_action_catalog()
RESTART_TARGETS = {item["id"] for item in RESTART_CATALOG}
SMART_TARGETS = {"system-ssd", "storage-hdd"}
ACTIONS = {"restart", "backup", "smart-short", "reboot", "shutdown"}

password_hasher = PasswordHasher()


@dataclass
class Session:
    username: str
    csrf: str
    created_at: float
    last_seen: float


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=80)
    password: str = Field(min_length=1, max_length=512)


class ActionRequest(BaseModel):
    target: str | None = Field(default=None, max_length=80)
    confirmation: str = Field(default="", max_length=80)
    password: str | None = Field(default=None, max_length=512)


sessions: dict[str, Session] = {}
login_failures: dict[str, list[float]] = {}
jobs: dict[str, dict[str, Any]] = {}

app = FastAPI(title="HPServer Dock Dashboard", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


def client_ip(request: Request) -> str:
    trusted_client = request.headers.get("x-dashboard-client-ip", "").strip()
    if secure_proxy_request(request) and trusted_client:
        return trusted_client
    forwarded = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
    return forwarded or (request.client.host if request.client else "unknown")


def secure_proxy_request(request: Request) -> bool:
    token = request.headers.get("x-dashboard-proxy-token", "")
    return bool(PROXY_TOKEN) and secrets.compare_digest(token, PROXY_TOKEN)


def verify_origin(request: Request) -> None:
    origin = request.headers.get("origin")
    if origin and origin != f"https://{DASHBOARD_HOST}":
        raise HTTPException(status_code=403, detail="Invalid request origin")


def verify_password(password: str) -> bool:
    if not PASSWORD_HASH:
        return False
    try:
        return password_hasher.verify(PASSWORD_HASH, password)
    except (VerifyMismatchError, InvalidHashError):
        return False


def active_session(token: str | None) -> Session | None:
    if not token:
        return None
    session = sessions.get(token)
    if not session:
        return None
    now = time.time()
    if now - session.last_seen > SESSION_IDLE_SECONDS or now - session.created_at > SESSION_MAX_SECONDS:
        sessions.pop(token, None)
        return None
    session.last_seen = now
    return session


def require_session(token: str | None, csrf: str | None = None, verify_csrf: bool = False) -> Session:
    session = active_session(token)
    if not session:
        raise HTTPException(status_code=401, detail="Authentication required")
    if verify_csrf and (not csrf or not secrets.compare_digest(session.csrf, csrf)):
        raise HTTPException(status_code=403, detail="Invalid CSRF token")
    return session


def enforce_login_rate_limit(ip: str) -> None:
    cutoff = time.time() - LOGIN_WINDOW_SECONDS
    recent = [stamp for stamp in login_failures.get(ip, []) if stamp >= cutoff]
    login_failures[ip] = recent
    if len(recent) >= LOGIN_MAX_FAILURES:
        raise HTTPException(status_code=429, detail="Too many failed login attempts")


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self'; style-src 'self'; "
        "img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
    )
    if secure_proxy_request(request):
        response.headers["Strict-Transport-Security"] = "max-age=31536000"
    return response


@app.get("/", include_in_schema=False)
async def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/v1/status")
async def status() -> JSONResponse:
    try:
        payload = json.loads(STATUS_FILE.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        payload = {
            "generated_at": None,
            "stale": True,
            "summary": {"state": "unknown"},
            "alerts": [{"level": "warning", "message": "Status collector has not produced data yet"}],
        }
    generated = payload.get("generated_at_epoch")
    payload["stale"] = not isinstance(generated, (int, float)) or time.time() - generated > 45
    return JSONResponse(payload, headers={"Cache-Control": "no-store"})


@app.get("/api/v1/catalog")
async def catalog() -> dict[str, Any]:
    return {
        "restart_targets": RESTART_CATALOG,
        "smart_targets": [
            {"id": "system-ssd", "label": "System SSD"},
            {"id": "storage-hdd", "label": "Storage HDD"},
        ],
    }


@app.post("/api/v1/auth/login")
async def login(body: LoginRequest, request: Request, response: Response) -> dict[str, Any]:
    if not secure_proxy_request(request):
        raise HTTPException(status_code=403, detail="Login is available only through the HTTPS dashboard")
    verify_origin(request)
    ip = client_ip(request)
    enforce_login_rate_limit(ip)
    valid_user = secrets.compare_digest(body.username, USERNAME)
    if not valid_user or not verify_password(body.password):
        login_failures.setdefault(ip, []).append(time.time())
        await asyncio.sleep(0.35)
        raise HTTPException(status_code=401, detail="Invalid credentials")

    login_failures.pop(ip, None)
    token = secrets.token_urlsafe(32)
    csrf = secrets.token_urlsafe(24)
    now = time.time()
    sessions[token] = Session(username=USERNAME, csrf=csrf, created_at=now, last_seen=now)
    response.set_cookie(
        COOKIE_NAME,
        token,
        max_age=SESSION_MAX_SECONDS,
        secure=True,
        httponly=True,
        samesite="strict",
        path="/",
    )
    return {"authenticated": True, "username": USERNAME, "csrf": csrf}


@app.get("/api/v1/auth/session")
async def session_status(hp_dashboard_session: str | None = Cookie(default=None)) -> dict[str, Any]:
    session = active_session(hp_dashboard_session)
    if not session:
        return {"authenticated": False}
    return {"authenticated": True, "username": session.username, "csrf": session.csrf}


@app.post("/api/v1/auth/logout")
async def logout(
    request: Request,
    response: Response,
    hp_dashboard_session: str | None = Cookie(default=None),
    x_csrf_token: str | None = Header(default=None),
) -> dict[str, bool]:
    if not secure_proxy_request(request):
        raise HTTPException(status_code=403, detail="HTTPS required")
    require_session(hp_dashboard_session, x_csrf_token, verify_csrf=True)
    if hp_dashboard_session:
        sessions.pop(hp_dashboard_session, None)
    response.delete_cookie(COOKIE_NAME, path="/")
    return {"authenticated": False}


async def execute_job(job_id: str, args: list[str]) -> None:
    jobs[job_id]["state"] = "running"
    jobs[job_id]["started_at"] = int(time.time())
    try:
        process = await asyncio.create_subprocess_exec(
            "sudo",
            "-n",
            ACTION_HELPER,
            *args,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        output, _ = await asyncio.wait_for(process.communicate(), timeout=120)
        jobs[job_id]["state"] = "succeeded" if process.returncode == 0 else "failed"
        jobs[job_id]["message"] = output.decode("utf-8", "replace")[-2000:].strip()
    except asyncio.TimeoutError:
        jobs[job_id]["state"] = "failed"
        jobs[job_id]["message"] = "Action timed out"
    except Exception as exc:  # pragma: no cover - defensive runtime boundary
        jobs[job_id]["state"] = "failed"
        jobs[job_id]["message"] = f"Action runner failed: {type(exc).__name__}"
    finally:
        jobs[job_id]["finished_at"] = int(time.time())


@app.post("/api/v1/actions/{action_id}", status_code=202)
async def run_action(
    action_id: str,
    body: ActionRequest,
    request: Request,
    hp_dashboard_session: str | None = Cookie(default=None),
    x_csrf_token: str | None = Header(default=None),
) -> dict[str, str]:
    if not secure_proxy_request(request):
        raise HTTPException(status_code=403, detail="Actions are available only through the HTTPS dashboard")
    verify_origin(request)
    session = require_session(hp_dashboard_session, x_csrf_token, verify_csrf=True)
    if action_id not in ACTIONS:
        raise HTTPException(status_code=404, detail="Unknown action")

    args: list[str]
    if action_id == "restart":
        if body.target not in RESTART_TARGETS or body.confirmation != "CONFIRM":
            raise HTTPException(status_code=400, detail="Invalid restart request")
        args = ["restart", body.target]
    elif action_id == "smart-short":
        if body.target not in SMART_TARGETS or body.confirmation != "CONFIRM":
            raise HTTPException(status_code=400, detail="Invalid SMART request")
        args = ["smart-short", body.target]
    elif action_id == "backup":
        if body.target is not None or body.confirmation != "CONFIRM":
            raise HTTPException(status_code=400, detail="Invalid backup request")
        args = ["backup"]
    else:
        if body.target is not None or body.confirmation != "hp-server" or not body.password:
            raise HTTPException(status_code=400, detail="Hostname and password confirmation required")
        if not verify_password(body.password):
            raise HTTPException(status_code=401, detail="Password confirmation failed")
        args = [action_id]

    job_id = secrets.token_urlsafe(12)
    jobs[job_id] = {
        "id": job_id,
        "state": "queued",
        "action": action_id,
        "target": body.target,
        "requested_by": session.username,
        "requested_from": client_ip(request),
        "created_at": int(time.time()),
    }
    asyncio.create_task(execute_job(job_id, args))
    return {"job_id": job_id, "state": "queued"}


@app.get("/api/v1/jobs/{job_id}")
async def job_status(
    job_id: str,
    request: Request,
    hp_dashboard_session: str | None = Cookie(default=None),
) -> dict[str, Any]:
    if not secure_proxy_request(request):
        raise HTTPException(status_code=403, detail="HTTPS required")
    require_session(hp_dashboard_session)
    job = jobs.get(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job
