from __future__ import annotations

import importlib
import os
import sys
from pathlib import Path

from argon2 import PasswordHasher
from fastapi.testclient import TestClient


SERVICE_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVICE_DIR / "app"))

os.environ["DASHBOARD_USERNAME"] = "butenko"
os.environ["DASHBOARD_PASSWORD_HASH"] = PasswordHasher().hash("correct-horse-battery")
os.environ["DASHBOARD_PROXY_TOKEN"] = "test-proxy-token"
os.environ["DASHBOARD_HOST"] = "dashboard.butenko.online"
os.environ["DASHBOARD_ACTION_HELPER"] = "/bin/false"
main = importlib.import_module("main")
client = TestClient(main.app)
proxy_headers = {"X-Dashboard-Proxy-Token": "test-proxy-token", "Origin": "https://dashboard.butenko.online"}


def login() -> tuple[dict[str, str], str]:
    response = client.post(
        "/api/v1/auth/login",
        headers=proxy_headers,
        json={"username": "butenko", "password": "correct-horse-battery"},
    )
    assert response.status_code == 200
    return {**proxy_headers, "X-CSRF-Token": response.json()["csrf"]}, response.cookies[main.COOKIE_NAME]


def test_direct_http_login_is_denied() -> None:
    response = client.post(
        "/api/v1/auth/login",
        json={"username": "butenko", "password": "correct-horse-battery"},
    )
    assert response.status_code == 403


def test_wrong_password_is_denied() -> None:
    response = client.post(
        "/api/v1/auth/login",
        headers=proxy_headers,
        json={"username": "butenko", "password": "wrong-password"},
    )
    assert response.status_code == 401


def test_unknown_action_and_target_are_rejected() -> None:
    headers, token = login()
    cookies = {main.COOKIE_NAME: token}
    unknown = client.post("/api/v1/actions/shell", headers=headers, cookies=cookies, json={"confirmation": "CONFIRM"})
    bad_target = client.post(
        "/api/v1/actions/restart",
        headers=headers,
        cookies=cookies,
        json={"target": "jellyfin;id", "confirmation": "CONFIRM"},
    )
    assert unknown.status_code == 404
    assert bad_target.status_code == 400


def test_action_requires_csrf() -> None:
    headers, token = login()
    headers.pop("X-CSRF-Token")
    response = client.post(
        "/api/v1/actions/restart",
        headers=headers,
        cookies={main.COOKIE_NAME: token},
        json={"target": "jellyfin", "confirmation": "CONFIRM"},
    )
    assert response.status_code == 403
