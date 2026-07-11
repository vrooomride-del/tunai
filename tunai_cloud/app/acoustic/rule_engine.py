"""
Rule Engine placeholder — Phase AI-B.

This module will translate Acoustic Intent into safe, policy-checked
action descriptors. It does NOT generate DSP register values, PEQ
parameters, biquad coefficients, or any hardware write payloads.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass(frozen=True)
class AcousticAction:
    type: str
    policy: str
    requires_measurement: bool
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "type": self.type,
            "policy": self.policy,
            "requires_measurement": self.requires_measurement,
            **({"metadata": self.metadata} if self.metadata else {}),
        }


class RuleEngine:
    """
    Phase AI-B placeholder.

    Currently returns symbolic action descriptors only.
    Future phases will consult speaker capability profiles,
    measurement data, and safety constraints before producing
    any action descriptors.

    NEVER generates frequency values, gain values, or DSP addresses.
    """

    def derive_actions(
        self,
        intent: dict[str, str],
        has_room_scan: bool,
        speaker_profile: str | None,
    ) -> list[dict[str, Any]]:
        actions: list[AcousticAction] = []

        if intent.get("bass_boom") == "reduce":
            actions.append(
                AcousticAction(
                    type="reduce_bass_buildup",
                    policy="consumer_safe",
                    requires_measurement=True,
                )
            )

        if intent.get("vocal_clarity") == "increase":
            actions.append(
                AcousticAction(
                    type="enhance_vocal_presence",
                    policy="consumer_safe",
                    requires_measurement=has_room_scan,
                )
            )

        if intent.get("fatigue") == "avoid":
            actions.append(
                AcousticAction(
                    type="reduce_listening_fatigue",
                    policy="consumer_safe",
                    requires_measurement=False,
                )
            )

        return [a.to_dict() for a in actions]
