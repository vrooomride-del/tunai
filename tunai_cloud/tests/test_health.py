import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health_200():
    res = client.get("/health")
    assert res.status_code == 200


def test_health_body():
    body = client.get("/health").json()
    assert body["status"] == "ok"
    assert body["service"] == "tunai-cloud"
    assert "version" in body


def test_health_no_secrets():
    body = client.get("/health").json()
    for key in ("api_key", "GEMINI_API_KEY", "secret", "password", "token"):
        assert key not in str(body).lower() or body.get(key) is None
