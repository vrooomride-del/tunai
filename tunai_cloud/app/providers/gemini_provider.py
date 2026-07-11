from __future__ import annotations

import asyncio
import json
import logging
import re
import uuid
from typing import Any

from google import genai
from google.genai import types as genai_types

from app.config import settings
from app.orchestrator.prompts import SYSTEM_INSTRUCTION, build_user_prompt
from app.orchestrator.schemas import (
    AcousticIntent,
    Explanation,
    IntentValue,
    InterpretRequest,
    InterpretResponse,
    Strength,
    Tone,
)
from app.providers.base import AIProvider

logger = logging.getLogger(__name__)

_FORBIDDEN_DSP_KEYS = frozenset(
    {
        "frequency",
        "gain_db",
        "gainDb",
        "q",
        "biquad",
        "register",
        "address",
        "crossover",
        "limiter",
        "delay_ms",
        "delayMs",
        "safeload",
        "coefficient",
    }
)


def _mask_key(key: str) -> str:
    if len(key) <= 8:
        return "***"
    return key[:4] + "***"


def _extract_json(text: str) -> dict[str, Any]:
    """Extract JSON from model response. Handles markdown fences."""
    text = text.strip()
    # Strip markdown fences
    fenced = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
    if fenced:
        text = fenced.group(1)
    # Find first complete JSON object
    start = text.find("{")
    if start == -1:
        raise ValueError("No JSON object found in response")
    depth = 0
    for i, ch in enumerate(text[start:], start):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return json.loads(text[start : i + 1])
    raise ValueError("Incomplete JSON object in response")


def _check_forbidden_dsp(data: dict[str, Any]) -> None:
    """Reject response if it contains forbidden DSP keys anywhere."""
    def _walk(obj: Any) -> None:
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k in _FORBIDDEN_DSP_KEYS:
                    raise ValueError(f"Response contains forbidden DSP field: {k!r}")
                _walk(v)
        elif isinstance(obj, list):
            for item in obj:
                _walk(item)

    _walk(data)


def _parse_response(data: dict[str, Any], request_id: str) -> InterpretResponse:
    _check_forbidden_dsp(data)

    raw_intent = data.get("intent", {})
    intent = AcousticIntent(
        bass_boom=IntentValue(raw_intent.get("bass_boom", "none")),
        vocal_clarity=IntentValue(raw_intent.get("vocal_clarity", "none")),
        stereo_image=IntentValue(raw_intent.get("stereo_image", "preserve")),
        fatigue=IntentValue(raw_intent.get("fatigue", "avoid")),
    )

    raw_exp = data.get("explanation", {})
    explanation = Explanation(
        summary=str(raw_exp.get("summary", "")),
        what_tunai_found=[str(s) for s in raw_exp.get("what_tunai_found", [])],
    )

    return InterpretResponse(
        request_id=request_id,
        intent=intent,
        strength=Strength(data.get("strength", "medium")),
        tone=Tone(data.get("tone", "natural")),
        requires_room_scan=bool(data.get("requires_room_scan", True)),
        requires_confirmation=True,
        explanation=explanation,
        source="gemini",
    )


class GeminiProvider(AIProvider):
    def __init__(self) -> None:
        if not settings.GEMINI_API_KEY:
            raise RuntimeError("GEMINI_API_KEY is not configured")
        self._client = genai.Client(api_key=settings.GEMINI_API_KEY)
        self._model = settings.GEMINI_MODEL or "gemini-2.5-flash"

    async def interpret(self, request: InterpretRequest) -> InterpretResponse:
        request_id = str(uuid.uuid4())

        # Build compact room scan summary (send only what's needed — no raw payload)
        room_scan_summary: str | None = None
        if request.room_scan:
            scan = request.room_scan
            parts = []
            if scan.room_type:
                parts.append(f"room_type={scan.room_type}")
            if scan.sound_score is not None:
                parts.append(f"sound_score={scan.sound_score}")
            if scan.peaks:
                peak_strs = [
                    f"{p.frequency:.0f}Hz/{p.gain_db:+.1f}dB"
                    + (f"/Q{p.q:.1f}" if p.q else "")
                    for p in scan.peaks[:5]  # cap at 5 peaks
                ]
                parts.append(f"peaks=[{', '.join(peak_strs)}]")
            room_scan_summary = " ".join(parts) if parts else None

        speaker_summary: str | None = None
        if request.speaker:
            s = request.speaker
            speaker_summary = " ".join(
                p
                for p in [
                    f"model={s.model}" if s.model else None,
                    f"profile={s.profile}" if s.profile else None,
                ]
                if p
            ) or None

        prompt = build_user_prompt(
            request.user_text, request.locale, room_scan_summary, speaker_summary
        )

        logger.info(
            "gemini_request",
            extra={
                "request_id": request_id,
                "model": self._model,
                "has_room_scan": room_scan_summary is not None,
            },
        )

        try:
            response = await asyncio.wait_for(
                asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self._client.models.generate_content(
                        model=self._model,
                        contents=prompt,
                        config=genai_types.GenerateContentConfig(
                            system_instruction=SYSTEM_INSTRUCTION,
                            temperature=0.1,
                            response_mime_type="application/json",
                        ),
                    ),
                ),
                timeout=settings.REQUEST_TIMEOUT_SECONDS,
            )
        except asyncio.TimeoutError:
            raise TimeoutError(f"Gemini request timed out after {settings.REQUEST_TIMEOUT_SECONDS}s")

        raw_text = response.text
        if not raw_text:
            raise ValueError("Gemini returned empty response")

        try:
            data = _extract_json(raw_text)
        except (json.JSONDecodeError, ValueError) as e:
            raise ValueError(f"Could not parse Gemini response as JSON: {e}") from e

        return _parse_response(data, request_id)
