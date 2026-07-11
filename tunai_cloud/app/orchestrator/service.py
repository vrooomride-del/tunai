from __future__ import annotations

import logging
import uuid

from app.config import settings
from app.orchestrator.schemas import (
    AcousticIntent,
    Explanation,
    IntentValue,
    InterpretRequest,
    InterpretResponse,
    Strength,
    Tone,
)
from app.providers.base import AIProvider, ProviderNotConfiguredError

logger = logging.getLogger(__name__)

# Simple deterministic keyword fallback (Korean + English)
_KEYWORD_MAP: list[tuple[list[str], str, IntentValue]] = [
    (["저음", "베이스", "울림", "벙벙", "부밍", "bass", "boom"], "bass_boom", IntentValue.reduce),
    (["보컬", "목소리", "선명", "또렷", "clarity", "vocal"], "vocal_clarity", IntentValue.increase),
    (["피곤", "날카롭", "쏨", "자극", "fatigue", "harsh", "bright"], "fatigue", IntentValue.avoid),
    (["공간감", "스테레오", "무대", "stereo", "stage", "wide"], "stereo_image", IntentValue.preserve),
]


def _deterministic_fallback(user_text: str) -> AcousticIntent:
    """Classify intent from user_text using keyword matching only."""
    bass_boom = IntentValue.none
    vocal_clarity = IntentValue.none
    stereo_image = IntentValue.preserve
    fatigue = IntentValue.avoid

    lower = user_text.lower()
    for keywords, field, value in _KEYWORD_MAP:
        if any(kw in lower for kw in keywords):
            if field == "bass_boom":
                bass_boom = value
            elif field == "vocal_clarity":
                vocal_clarity = value
            elif field == "fatigue":
                fatigue = value
            elif field == "stereo_image":
                stereo_image = value

    return AcousticIntent(
        bass_boom=bass_boom,
        vocal_clarity=vocal_clarity,
        stereo_image=stereo_image,
        fatigue=fatigue,
    )


def _fallback_response(request: InterpretRequest, request_id: str) -> InterpretResponse:
    intent = _deterministic_fallback(request.user_text)
    return InterpretResponse(
        request_id=request_id,
        intent=intent,
        strength=Strength.medium,
        tone=Tone.natural,
        requires_room_scan=request.room_scan is None,
        requires_confirmation=True,
        explanation=Explanation(
            summary=(
                "AI provider를 일시적으로 사용할 수 없어 기본 분석을 제공합니다. "
                "잠시 후 다시 시도해 주세요."
            ),
            what_tunai_found=[
                f"사용자 요청: {request.user_text[:80]}"
                + ("..." if len(request.user_text) > 80 else "")
            ],
        ),
        source="fallback",
    )


def _build_provider() -> AIProvider:
    provider_name = settings.AI_PROVIDER
    if provider_name == "gemini":
        from app.providers.gemini_provider import GeminiProvider
        return GeminiProvider()
    if provider_name == "openai":
        from app.providers.openai_provider import OpenAIProvider
        return OpenAIProvider()
    if provider_name == "claude":
        from app.providers.claude_provider import ClaudeProvider
        return ClaudeProvider()
    raise ValueError(f"Unknown AI_PROVIDER: {provider_name!r}")


class AIOrchestratorService:
    async def interpret(self, request: InterpretRequest) -> InterpretResponse:
        request_id = str(uuid.uuid4())

        try:
            provider = _build_provider()
        except (RuntimeError, ValueError) as e:
            logger.warning("provider_init_failed provider=%s error=%s", settings.AI_PROVIDER, str(e))
            return _fallback_response(request, request_id)

        try:
            response = await provider.interpret(request)
        except ProviderNotConfiguredError as e:
            logger.warning("provider_not_configured provider=%s", settings.AI_PROVIDER)
            return _fallback_response(request, request_id)
        except TimeoutError:
            logger.warning("provider_timeout provider=%s request_id=%s", settings.AI_PROVIDER, request_id)
            return _fallback_response(request, request_id)
        except (ValueError, KeyError) as e:
            logger.warning(
                "provider_parse_error provider=%s request_id=%s error=%s",
                settings.AI_PROVIDER, request_id, str(e),
            )
            return _fallback_response(request, request_id)
        except Exception as e:
            logger.error(
                "provider_unexpected_error provider=%s request_id=%s error=%s",
                settings.AI_PROVIDER, request_id, type(e).__name__,
            )
            return _fallback_response(request, request_id)

        # Guardrail: requires_confirmation is always True
        object.__setattr__(response, "requires_confirmation", True)

        logger.info(
            "interpret_success request_id=%s source=%s strength=%s",
            response.request_id, response.source, response.strength,
        )
        return response
