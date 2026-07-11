from __future__ import annotations

from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator


class IntentValue(str, Enum):
    none = "none"
    reduce = "reduce"
    increase = "increase"
    preserve = "preserve"
    avoid = "avoid"


class Strength(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"


class Tone(str, Enum):
    natural = "natural"
    warm = "warm"
    clear = "clear"
    studio = "studio"
    vocal = "vocal"


# ── Request ───────────────────────────────────────────────────────────────────

class FrequencyPeak(BaseModel):
    model_config = {"extra": "forbid"}

    frequency: float
    gain_db: float
    q: Optional[float] = None

    @field_validator("frequency")
    @classmethod
    def frequency_positive(cls, v: float) -> float:
        if v <= 0:
            raise ValueError("frequency must be positive")
        return v

    @field_validator("q")
    @classmethod
    def q_positive(cls, v: Optional[float]) -> Optional[float]:
        if v is not None and v <= 0:
            raise ValueError("q must be positive")
        return v


class RoomScanSummary(BaseModel):
    model_config = {"extra": "forbid"}

    room_type: Optional[str] = None
    sound_score: Optional[int] = None
    peaks: list[FrequencyPeak] = Field(default_factory=list)

    @field_validator("sound_score")
    @classmethod
    def sound_score_range(cls, v: Optional[int]) -> Optional[int]:
        if v is not None and not (0 <= v <= 100):
            raise ValueError("sound_score must be 0-100")
        return v


class SpeakerSummary(BaseModel):
    model_config = {"extra": "forbid"}

    model: Optional[str] = None
    profile: Optional[str] = None


class InterpretRequest(BaseModel):
    model_config = {"extra": "ignore"}  # ignore unknown client fields gracefully

    user_text: str = Field(..., min_length=1)
    locale: str = "ko-KR"
    room_scan: Optional[RoomScanSummary] = None
    speaker: Optional[SpeakerSummary] = None

    @model_validator(mode="after")
    def validate_user_text_length(self) -> "InterpretRequest":
        from app.config import settings
        if len(self.user_text) > settings.MAX_USER_TEXT_LENGTH:
            raise ValueError(
                f"user_text must be ≤ {settings.MAX_USER_TEXT_LENGTH} characters"
            )
        return self


# ── Response ──────────────────────────────────────────────────────────────────

class AcousticIntent(BaseModel):
    model_config = {"extra": "forbid"}

    bass_boom: IntentValue = IntentValue.none
    vocal_clarity: IntentValue = IntentValue.none
    stereo_image: IntentValue = IntentValue.preserve
    fatigue: IntentValue = IntentValue.avoid


class Explanation(BaseModel):
    model_config = {"extra": "forbid"}

    summary: str
    what_tunai_found: list[str] = Field(default_factory=list)


class InterpretResponse(BaseModel):
    model_config = {"extra": "forbid"}

    request_id: str
    intent: AcousticIntent
    strength: Strength = Strength.medium
    tone: Tone = Tone.natural
    requires_room_scan: bool
    requires_confirmation: bool = True
    explanation: Explanation
    source: str
