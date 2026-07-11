"""
Shared fixtures. Gemini provider is mocked in all interpret tests.
External Gemini API is never called during unit tests.
"""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch

from app.orchestrator.schemas import (
    AcousticIntent,
    Explanation,
    IntentValue,
    InterpretResponse,
    Strength,
    Tone,
)


GOOD_RESPONSE = InterpretResponse(
    request_id="test-id-123",
    intent=AcousticIntent(
        bass_boom=IntentValue.reduce,
        vocal_clarity=IntentValue.increase,
        stereo_image=IntentValue.preserve,
        fatigue=IntentValue.avoid,
    ),
    strength=Strength.medium,
    tone=Tone.natural,
    requires_room_scan=False,
    requires_confirmation=True,
    explanation=Explanation(
        summary="저역 울림을 줄이고 보컬을 더 또렷하게 조정합니다.",
        what_tunai_found=["사용자가 저역 울림 완화를 요청했습니다.", "사용자가 보컬 명료도 개선을 요청했습니다."],
    ),
    source="gemini",
)


@pytest.fixture()
def client_with_mock_gemini():
    """TestClient with GeminiProvider mocked to return GOOD_RESPONSE."""
    from app.main import app

    with patch(
        "app.orchestrator.service._build_provider"
    ) as mock_build:
        mock_provider = AsyncMock()
        mock_provider.interpret = AsyncMock(return_value=GOOD_RESPONSE)
        mock_build.return_value = mock_provider
        with TestClient(app) as c:
            yield c


@pytest.fixture()
def client_with_timeout():
    """TestClient where provider raises TimeoutError."""
    from app.main import app

    with patch("app.orchestrator.service._build_provider") as mock_build:
        mock_provider = AsyncMock()
        mock_provider.interpret = AsyncMock(side_effect=TimeoutError("timed out"))
        mock_build.return_value = mock_provider
        with TestClient(app) as c:
            yield c


@pytest.fixture()
def client_with_malformed_json():
    """TestClient where provider raises ValueError (malformed JSON)."""
    from app.main import app

    with patch("app.orchestrator.service._build_provider") as mock_build:
        mock_provider = AsyncMock()
        mock_provider.interpret = AsyncMock(
            side_effect=ValueError("Could not parse response as JSON")
        )
        mock_build.return_value = mock_provider
        with TestClient(app) as c:
            yield c


@pytest.fixture()
def client_with_provider_exception():
    """TestClient where provider raises unexpected exception."""
    from app.main import app

    with patch("app.orchestrator.service._build_provider") as mock_build:
        mock_provider = AsyncMock()
        mock_provider.interpret = AsyncMock(side_effect=RuntimeError("network error"))
        mock_build.return_value = mock_provider
        with TestClient(app) as c:
            yield c


@pytest.fixture()
def plain_client():
    """TestClient without any provider mock (uses fallback or real provider)."""
    from app.main import app
    with TestClient(app) as c:
        yield c
