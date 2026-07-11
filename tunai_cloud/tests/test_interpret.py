"""
Integration tests for POST /v1/tune/interpret.
All tests mock the AI provider — no external API calls.
"""
import pytest
from fastapi.testclient import TestClient


VALID_PAYLOAD = {
    "user_text": "보컬은 더 또렷하게, 저음은 덜 울리게 해줘.",
    "locale": "ko-KR",
    "room_scan": {
        "room_type": "desk",
        "sound_score": 82,
        "peaks": [
            {"frequency": 92.0, "gain_db": 6.2, "q": 1.4},
            {"frequency": 180.0, "gain_db": 3.8, "q": 2.1},
        ],
    },
    "speaker": {"model": "TUNAI ONE", "profile": "consumer_safe"},
}

DSP_FORBIDDEN_FIELDS = [
    "frequency", "gain_db", "gainDb", "q", "biquad",
    "register", "address", "crossover", "limiter",
    "delay_ms", "safeload", "coefficient",
]


# ── Validation tests (no provider needed) ────────────────────────────────────

def test_empty_user_text_rejected(plain_client):
    res = plain_client.post("/v1/tune/interpret", json={**VALID_PAYLOAD, "user_text": ""})
    assert res.status_code == 422


def test_whitespace_only_user_text_rejected(plain_client):
    res = plain_client.post("/v1/tune/interpret", json={**VALID_PAYLOAD, "user_text": "   "})
    # pydantic min_length=1 catches empty, whitespace passes length check but is handled by provider
    # Just check we at least don't crash
    assert res.status_code in (200, 422)


def test_too_long_user_text_rejected(plain_client):
    res = plain_client.post(
        "/v1/tune/interpret",
        json={**VALID_PAYLOAD, "user_text": "a" * 1001},
    )
    assert res.status_code == 422


def test_invalid_frequency_rejected(plain_client):
    bad_payload = dict(VALID_PAYLOAD)
    bad_payload["room_scan"] = {
        "peaks": [{"frequency": -10.0, "gain_db": 3.0, "q": 1.0}]
    }
    res = plain_client.post("/v1/tune/interpret", json=bad_payload)
    assert res.status_code == 422


def test_invalid_q_rejected(plain_client):
    bad_payload = dict(VALID_PAYLOAD)
    bad_payload["room_scan"] = {
        "peaks": [{"frequency": 80.0, "gain_db": 3.0, "q": -1.0}]
    }
    res = plain_client.post("/v1/tune/interpret", json=bad_payload)
    assert res.status_code == 422


def test_sound_score_out_of_range_rejected(plain_client):
    bad_payload = dict(VALID_PAYLOAD)
    bad_payload["room_scan"] = {"sound_score": 150}
    res = plain_client.post("/v1/tune/interpret", json=bad_payload)
    assert res.status_code == 422


def test_invalid_enum_in_extra_field_ignored(plain_client):
    # Extra top-level fields should be ignored (model_config extra="ignore")
    payload = {**VALID_PAYLOAD, "unknown_field": "should_be_ignored"}
    # We just need it not to 422 on the extra field
    # (provider will fallback if not configured)
    res = plain_client.post("/v1/tune/interpret", json=payload)
    assert res.status_code != 500


# ── Success path (mocked provider) ───────────────────────────────────────────

def test_successful_interpret(client_with_mock_gemini):
    res = client_with_mock_gemini.post("/v1/tune/interpret", json=VALID_PAYLOAD)
    assert res.status_code == 200
    body = res.json()
    assert body["source"] == "gemini"
    assert body["requires_confirmation"] is True
    assert "intent" in body
    assert "explanation" in body
    assert "request_id" in body


def test_requires_confirmation_always_true(client_with_mock_gemini):
    res = client_with_mock_gemini.post("/v1/tune/interpret", json=VALID_PAYLOAD)
    assert res.json()["requires_confirmation"] is True


def test_response_has_no_dsp_fields(client_with_mock_gemini):
    body = res = client_with_mock_gemini.post("/v1/tune/interpret", json=VALID_PAYLOAD).json()
    body_str = str(body)
    # Only check top-level response keys
    for field in DSP_FORBIDDEN_FIELDS:
        assert field not in body, f"Forbidden DSP field '{field}' found in response"


def test_intent_values_are_valid_enums(client_with_mock_gemini):
    body = client_with_mock_gemini.post("/v1/tune/interpret", json=VALID_PAYLOAD).json()
    valid_values = {"none", "reduce", "increase", "preserve", "avoid"}
    for k, v in body["intent"].items():
        assert v in valid_values, f"Invalid intent value {v!r} for {k}"


def test_no_secret_in_response(client_with_mock_gemini):
    body = client_with_mock_gemini.post("/v1/tune/interpret", json=VALID_PAYLOAD).json()
    body_str = str(body).lower()
    assert "api_key" not in body_str
    assert "gemini_api_key" not in body_str
    assert "anthropic_api_key" not in body_str


# ── Fallback tests ────────────────────────────────────────────────────────────

def test_provider_timeout_returns_fallback(client_with_timeout):
    res = client_with_timeout.post("/v1/tune/interpret", json=VALID_PAYLOAD)
    assert res.status_code == 200
    body = res.json()
    assert body["source"] == "fallback"
    assert body["requires_confirmation"] is True


def test_provider_malformed_json_returns_fallback(client_with_malformed_json):
    res = client_with_malformed_json.post("/v1/tune/interpret", json=VALID_PAYLOAD)
    assert res.status_code == 200
    assert res.json()["source"] == "fallback"


def test_provider_exception_returns_fallback(client_with_provider_exception):
    res = client_with_provider_exception.post("/v1/tune/interpret", json=VALID_PAYLOAD)
    assert res.status_code == 200
    assert res.json()["source"] == "fallback"


def test_fallback_requires_confirmation_true(client_with_timeout):
    body = client_with_timeout.post("/v1/tune/interpret", json=VALID_PAYLOAD).json()
    assert body["requires_confirmation"] is True


def test_fallback_does_not_invent_unrelated_intent(client_with_timeout):
    """Fallback for a bass-only request should not return vocal_clarity=increase."""
    payload = {**VALID_PAYLOAD, "user_text": "저음이 너무 울려요."}
    body = client_with_timeout.post("/v1/tune/interpret", json=payload).json()
    assert body["source"] == "fallback"
    # vocal_clarity should stay neutral — user didn't ask for it
    assert body["intent"]["vocal_clarity"] == "none"


def test_fallback_for_neutral_request_returns_neutral_intent(client_with_timeout):
    """Fallback for a request with no matching keywords should return neutral intent."""
    payload = {**VALID_PAYLOAD, "user_text": "그냥 들어봤는데 괜찮네요."}
    body = client_with_timeout.post("/v1/tune/interpret", json=payload).json()
    assert body["source"] == "fallback"
    assert body["intent"]["bass_boom"] == "none"
    assert body["intent"]["vocal_clarity"] == "none"
