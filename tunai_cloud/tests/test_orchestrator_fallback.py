"""
Tests for AIOrchestratorService fallback behavior and provider placeholder handling.
"""
import pytest
from unittest.mock import patch, AsyncMock

from app.orchestrator.schemas import InterpretRequest
from app.orchestrator.service import AIOrchestratorService, _deterministic_fallback
from app.providers.base import ProviderNotConfiguredError


# ── Deterministic fallback keyword tests ─────────────────────────────────────

def test_keyword_fallback_bass():
    intent = _deterministic_fallback("저음이 너무 울려요")
    assert intent.bass_boom.value == "reduce"
    assert intent.vocal_clarity.value == "none"


def test_keyword_fallback_vocal():
    intent = _deterministic_fallback("보컬이 더 또렷했으면 해요")
    assert intent.vocal_clarity.value == "increase"
    assert intent.bass_boom.value == "none"


def test_keyword_fallback_both():
    intent = _deterministic_fallback("저음은 줄이고 보컬은 선명하게")
    assert intent.bass_boom.value == "reduce"
    assert intent.vocal_clarity.value == "increase"


def test_keyword_fallback_neutral():
    intent = _deterministic_fallback("그냥 좋았어요")
    assert intent.bass_boom.value == "none"
    assert intent.vocal_clarity.value == "none"
    assert intent.stereo_image.value == "preserve"
    assert intent.fatigue.value == "avoid"


def test_keyword_fallback_english_bass():
    intent = _deterministic_fallback("too much bass boom")
    assert intent.bass_boom.value == "reduce"


# ── Orchestrator fallback via service ────────────────────────────────────────

@pytest.mark.asyncio
async def test_openai_placeholder_triggers_fallback():
    with patch("app.orchestrator.service.settings") as mock_settings:
        mock_settings.AI_PROVIDER = "openai"
        mock_settings.MAX_USER_TEXT_LENGTH = 1000
        mock_settings.REQUEST_TIMEOUT_SECONDS = 20

        from app.providers.openai_provider import OpenAIProvider

        with patch("app.orchestrator.service._build_provider") as mock_build:
            provider = OpenAIProvider()
            mock_build.return_value = provider

            svc = AIOrchestratorService()
            req = InterpretRequest(user_text="보컬이 선명하게")
            result = await svc.interpret(req)

        assert result.source == "fallback"
        assert result.requires_confirmation is True


@pytest.mark.asyncio
async def test_claude_placeholder_triggers_fallback():
    from app.providers.claude_provider import ClaudeProvider

    with patch("app.orchestrator.service._build_provider") as mock_build:
        mock_build.return_value = ClaudeProvider()
        svc = AIOrchestratorService()
        req = InterpretRequest(user_text="저음 줄여줘")
        result = await svc.interpret(req)

    assert result.source == "fallback"
    assert result.requires_confirmation is True


@pytest.mark.asyncio
async def test_requires_confirmation_guardrail_always_true():
    """Even if provider returns requires_confirmation=False, orchestrator forces it True."""
    from app.orchestrator.schemas import (
        AcousticIntent, Explanation, IntentValue, InterpretResponse, Strength, Tone
    )
    bad_response = InterpretResponse(
        request_id="x",
        intent=AcousticIntent(),
        strength=Strength.medium,
        tone=Tone.natural,
        requires_room_scan=False,
        requires_confirmation=False,  # provider tried to set this
        explanation=Explanation(summary="test", what_tunai_found=[]),
        source="gemini",
    )
    with patch("app.orchestrator.service._build_provider") as mock_build:
        mock_provider = AsyncMock()
        mock_provider.interpret = AsyncMock(return_value=bad_response)
        mock_build.return_value = mock_provider

        svc = AIOrchestratorService()
        req = InterpretRequest(user_text="test request")
        result = await svc.interpret(req)

    assert result.requires_confirmation is True
