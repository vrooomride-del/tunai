# TUNAI Cloud — Phase AI-B Design

**Status:** Design only. No implementation in this document.
**Prerequisite:** Phase AI-A (Acoustic Intent classification via Gemini) must be stable in production.

---

## Overview

Phase AI-B introduces the structures and pipeline that sit between the raw
Acoustic Intent returned by the AI Orchestrator and any eventual DSP action.

The core principle remains unchanged:

```
AI interprets.
TUNAI validates.
DSP executes.
```

No LLM output ever becomes a DSP command without passing through:
1. Measurement Analyzer (what does the data actually show?)
2. Rule Engine (what corrective actions are acoustically appropriate?)
3. Safety Validator (what can this speaker safely do, given its capability profile?)
4. Filter Generator (translate approved actions into hardware-ready parameters)
5. User Confirmation (explicit opt-in, always)

---

## Data Structures

### MeasurementFeature

A single acoustic characteristic extracted from Room Scan measurement data.
This is a factual observation from measurement — never inferred or invented by LLM.

```python
@dataclass
class MeasurementFeature:
    feature_id: str          # UUID

    feature_type: Literal[
        "peak",               # localized energy excess
        "dip",                # localized energy deficit
        "tilt",               # broadband spectral slope anomaly
        "imbalance",          # left/right or high/low spectral imbalance
        "reflection_candidate",  # delayed energy pattern suggesting early reflection
    ]

    center_hz: float         # center frequency of the feature (Hz, > 0)
    level_db: float          # magnitude of the anomaly (positive = excess)
    q: float | None          # sharpness (None if not applicable, e.g. tilt)
    bandwidth_hz: float | None  # alternative to Q for broad features

    confidence: float        # 0.0–1.0, based on measurement signal quality
    evidence_source: Literal[
        "room_scan_fft",
        "user_report",       # user said "bass is boomy" — not a measurement
        "combined",          # measurement corroborated by user report
    ]
```

**Important:**
- `evidence_source = "user_report"` features must never produce concrete correction values.
- Only `"room_scan_fft"` or `"combined"` evidence justifies specific filter parameters.
- The Measurement Analyzer produces `MeasurementFeature` list; the LLM does not.

---

### SpeakerCapabilityProfile

Defines the safe operating envelope of a specific speaker model.
All values must be measured and validated by TUNAI engineering — never inferred.

```python
@dataclass
class SpeakerCapabilityProfile:
    speaker_model: str       # e.g. "TUNAI ONE"
    profile_version: str     # e.g. "1.0.0" — must be versioned

    # Frequency range within which EQ corrections are permitted
    safe_frequency_min_hz: float    # TBD_MEASURED
    safe_frequency_max_hz: float    # TBD_MEASURED

    # EQ gain limits
    max_eq_boost_db: float          # TBD_MEASURED — global boost ceiling
    max_low_frequency_boost_db: float  # TBD_MEASURED — stricter limit below ~200Hz
    max_cut_db: float               # TBD_MEASURED — usually less critical than boost

    # Filter structure limits
    supported_filter_count: int     # TBD_MEASURED — how many PEQ bands are safe
    allowed_q_range: tuple[float, float]  # (min_q, max_q), TBD_MEASURED

    # Policy
    headroom_policy: Literal[
        "conservative",  # protect driver integrity over fidelity
        "standard",      # balanced for typical consumer use
        "pro",           # allows tighter tolerances — requires operator knowledge
    ]

    mode: Literal["consumer", "pro"]

    # Thermal and excursion metadata (populated from T/S parameter measurements)
    fs_hz: float | None             # TBD_MEASURED
    xmax_mm: float | None           # TBD_MEASURED
    sensitivity_db: float | None    # TBD_MEASURED
```

**IMPORTANT:** No actual TUNAI ONE values have been confirmed.
Every `TBD_MEASURED` field must be filled in by TUNAI engineering based on
physical measurement before this structure is used to generate any corrections.

---

### CorrectionPlan

The bridge between Acoustic Intent and eventual filter parameters.
A `CorrectionPlan` describes *what to do* without yet specifying *exact filter values*.
Frequency, gain, and Q are determined by the Filter Generator in a later step,
constrained by `SpeakerCapabilityProfile` and `MeasurementFeature` data.

```python
@dataclass
class CorrectionAction:
    action_id: str
    action_type: Literal[
        "reduce_peak",
        "fill_dip",
        "tilt_correction",
        "vocal_presence_lift",
        "high_frequency_rolloff",
        "bass_extension_limit",
    ]

    # Which MeasurementFeature this action responds to (None = user preference only)
    target_feature_id: str | None

    # Approximate target region — NOT a confirmed filter frequency
    target_region: Literal[
        "sub_bass",     # < 80 Hz
        "bass",         # 80–250 Hz
        "low_mid",      # 250–800 Hz
        "mid",          # 800–2500 Hz
        "upper_mid",    # 2500–5000 Hz
        "presence",     # 5000–10000 Hz
        "air",          # > 10000 Hz
    ]

    # Approximate direction only — no dB values at this stage
    direction: Literal["cut", "boost", "shelf_cut", "shelf_boost", "no_change"]
    strength_hint: Literal["gentle", "moderate", "firm"]

    # Evidence basis for this action
    evidence_basis: Literal[
        "measurement_corroborated",  # MeasurementFeature with room_scan_fft evidence
        "user_preference_only",      # No measurement; user stated preference
    ]

    requires_measurement_confirmation: bool
    policy: str     # e.g. "consumer_safe", "pro_unlocked"


@dataclass
class CorrectionPlan:
    plan_id: str
    request_id: str              # links to the InterpretResponse
    acoustic_intent_summary: dict[str, str]   # bass_boom, vocal_clarity, etc.
    actions: list[CorrectionAction]
    has_measurement_evidence: bool
    speaker_model: str | None
    safety_pre_check_passed: bool
    created_at: str              # ISO 8601
```

**A `CorrectionPlan` never contains frequency/gain/Q values.**
Those are produced by the Filter Generator only after Safety Validator approval.

---

### SafetyValidationResult

The output of the Safety Validator after reviewing a `CorrectionPlan`
against a `SpeakerCapabilityProfile`.

```python
@dataclass
class SafetyValidationResult:
    validation_id: str
    plan_id: str
    speaker_model: str
    safety_policy_version: str   # e.g. "consumer_safe_v1"

    accepted_actions: list[str]  # action_ids approved as-is
    modified_actions: list[dict] # action_ids modified + what changed + why
    blocked_actions: list[dict]  # action_ids blocked + reason

    warnings: list[str]          # non-blocking notes (e.g. "near xmax limit")

    requires_user_confirmation: bool  # always True in Phase AI-A and AI-B
    overall_safe: bool           # True only if no blocked_actions remain

    # Blocked reasons use controlled vocabulary — no free-text from LLM
    # Example block reasons:
    #   "exceeds_max_low_frequency_boost"
    #   "no_speaker_capability_profile_available"
    #   "evidence_basis_insufficient_for_filter_generation"
    #   "frequency_below_safe_minimum"
```

**`requires_user_confirmation` is structurally always `True`.**
It cannot be set to `False` by any LLM output, any provider, or any service layer.

---

## Phase AI-B Pipeline

```
Room Scan (RoomScanResult)
    │
    ▼
Measurement Analyzer
    │  Input:  raw FFT / resonance peaks from RoomScanResult
    │  Output: list[MeasurementFeature]
    │  Rule:   never calls LLM; purely algorithmic
    │
    ▼
Acoustic Intent (from Phase AI-A Orchestrator)
    │  Input:  user_text + MeasurementFeature summaries
    │  Output: InterpretResponse (bass_boom, vocal_clarity, etc.)
    │  Rule:   LLM interprets user language; does NOT confirm measurements
    │
    ▼
Rule Engine
    │  Input:  InterpretResponse + list[MeasurementFeature]
    │  Output: CorrectionPlan
    │  Rule:   deterministic; no LLM; references SpeakerCapabilityProfile
    │
    ▼
Safety Validator
    │  Input:  CorrectionPlan + SpeakerCapabilityProfile
    │  Output: SafetyValidationResult
    │  Rule:   blocks anything that exceeds capability envelope
    │
    ▼
Filter Generator  (Phase AI-C)
    │  Input:  accepted CorrectionActions + MeasurementFeatures + CapabilityProfile
    │  Output: concrete filter parameters (frequency, gain_db, Q)
    │  Rule:   only reached after Safety Validator approves + user confirms
    │
    ▼
Preview (show user what will change — no DSP write yet)
    │
    ▼
User Confirmation (explicit tap)
    │
    ▼
DSP Payload → Write to hardware
```

---

## Phase AI-B Implementation Checklist

These items are NOT yet implemented. They are targets for Phase AI-B.

- [ ] `MeasurementAnalyzer` class that produces `MeasurementFeature` list from `RoomScanResult`
- [ ] `SpeakerCapabilityProfile` data for TUNAI ONE (requires physical measurement)
- [ ] `SpeakerCapabilityRegistry` — loads profiles by model name
- [ ] `RuleEngine.derive_correction_plan()` — replaces current placeholder
- [ ] `SafetyValidator.validate()` — replaces current placeholder
- [ ] Pydantic schemas for all structures above
- [ ] API endpoint `POST /v1/tune/plan` (returns `CorrectionPlan` without filter values)
- [ ] Unit tests for Rule Engine covering edge cases:
  - No measurement evidence → blocks filter generation
  - Bass boost below safe_frequency_min_hz → blocked
  - Capability profile missing → plan blocked entirely
- [ ] Authentication on all `/v1/` endpoints
- [ ] Rate limiting (token bucket or sliding window)
- [ ] Structured logging to external sink (before production)

---

## Invariants That Must Never Change

These rules apply in every phase, forever:

| Invariant | Enforcement point |
|-----------|------------------|
| `requires_user_confirmation = True` always | Orchestrator service (Phase AI-A), Safety Validator (Phase AI-B) |
| LLM output never becomes a DSP command | No path from `InterpretResponse` to DSP write without Rule Engine + Safety Validator |
| Bass boost forbidden without `SpeakerCapabilityProfile` | `SafetyValidationResult.blocked_actions` |
| Filter generation forbidden without measurement evidence | `CorrectionAction.requires_measurement_confirmation` |
| No LLM-generated frequency/gain/Q values in pipeline | Orchestrator schema forbids these fields (`extra="forbid"`) |
| AI key never in Flutter app binary | Feature flag + `TunaiCloudService`; key stays on server |

---

## Open Questions for Phase AI-B

1. **TUNAI ONE capability profile**: Who measures and certifies Fs, Xmax, sensitivity, and max safe EQ values? What measurement rig and procedure?
2. **Measurement Analyzer algorithm**: Peak detection from FFT — minimum confidence threshold? What signal-to-noise floor is required?
3. **Multiple speaker models**: How does `SpeakerCapabilityRegistry` handle unknown models? Block all corrections or use a conservative fallback profile?
4. **Consumer vs Pro unlock**: Should `headroom_policy = "pro"` be gated on the Pro Workbench license check?
5. **CorrectionPlan storage**: Does the plan need to be stored server-side for audit, or is it stateless per-request?
6. **Preview format**: What does the app show the user before confirmation — frequency response graph overlay, text description, or both?
