"""
Safety Validator placeholder — Phase AI-B.

Current policy (enforced at orchestrator level, not here yet):
- Auto-apply to DSP is FORBIDDEN without explicit user confirmation.
- Concrete correction values require measurement data.
- Bass boost without a verified speaker capability profile is FORBIDDEN.
- LLM output is NEVER treated as a safety-validated DSP command.

Future phases will add:
- Excursion / thermal limits per speaker model
- Amplifier headroom checks
- Frequency-specific gain ceiling tables
- Crossover compatibility checks
"""
from __future__ import annotations


class SafetyValidator:
    """
    Phase AI-B placeholder.

    Currently enforces the three invariants that must always hold:
    - No auto-apply (requires_confirmation must be True)
    - No LLM-generated DSP parameters passed through
    - No speaker-model-specific limits yet (requires Phase AI-B data)
    """

    INVARIANTS = [
        "Auto-apply to DSP is forbidden; user confirmation always required.",
        "LLM output must never be treated as a safety-validated DSP command.",
        "Bass boost is forbidden without a verified speaker capability profile.",
        "Concrete correction values require measurement data.",
    ]

    def validate_requires_confirmation(self, requires_confirmation: bool) -> None:
        if not requires_confirmation:
            raise ValueError(
                "Safety violation: requires_confirmation must always be True. "
                "Auto-apply to DSP is not permitted."
            )

    def check_no_dsp_fields(self, response_dict: dict) -> None:
        forbidden = {
            "frequency", "gain_db", "gainDb", "q", "biquad",
            "register", "address", "crossover", "limiter",
            "delay_ms", "safeload", "coefficient",
        }
        found = forbidden.intersection(response_dict.keys())
        if found:
            raise ValueError(
                f"Safety violation: response contains forbidden DSP fields: {found}"
            )
