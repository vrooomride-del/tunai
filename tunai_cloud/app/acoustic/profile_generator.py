"""
DSP Profile Generator placeholder — Phase AI-C.

This module will eventually translate validated AcousticActions into
hardware-ready DSP profiles. It will NEVER be called from AI output
directly; it requires:
1. Rule Engine approval
2. Safety Validator sign-off
3. Explicit user confirmation from the app

NEVER generates values in the current phase.
"""


class ProfileGenerator:
    """Phase AI-C placeholder. Not implemented."""

    def generate(self, *args, **kwargs) -> None:
        raise NotImplementedError(
            "DSP Profile Generator is not yet implemented. "
            "Requires Rule Engine + Safety Validator integration (Phase AI-C)."
        )
