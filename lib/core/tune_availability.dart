import 'consumer_sound_profile.dart';
import 'tune_plan.dart';

/// Single source of truth for "what can this Tune result screen show/do
/// right now" — replaces the previous scattered signals (a profile's
/// `resultCards` containing a 'measured_neutral' card, a separately-loaded
/// TunePlan checked only at Apply time, confidence checked ad hoc) that
/// could disagree with each other. Every consumer (title copy, the Room
/// Balance graph, the Apply button, and Apply itself) must derive its
/// decision from the SAME [TuneAvailability] value computed here from the
/// actual [TunePlan] — never from a proxy like `resultCards`.
enum TuneAvailability {
  /// A real, band-carrying TunePlan exists for this exact profile and
  /// confidence is acceptable — Apply may proceed.
  readyToApply,

  /// A real TunePlan exists for this exact profile but has zero bands — the
  /// room genuinely measured with nothing worth correcting. Never a
  /// candidate for Apply; never paired with a fabricated "after" curve.
  noCorrectionNeeded,

  /// Confidence is too low to treat the result as a finished analysis, OR
  /// there is no TunePlan matching this profile at all (missing/overwritten
  /// — TunePlanStore holds only one "current" plan, so an unrelated later
  /// save could otherwise silently leave a stale "ready" profile pointing
  /// at nothing). Both cases get the same honest answer: measure again.
  lowConfidence,
}

/// Pure, side-effect-free judgment used everywhere a Tune result screen
/// needs to know what to show. [plan] must be the actual TunePlan loaded
/// from storage for this session (see `currentTunePlanProvider` in
/// ai_screen.dart) — not assumed from [profile]'s cached fields.
TuneAvailability evaluateTuneAvailability({
  required TunePlan? plan,
  required ConsumerSoundProfile profile,
}) {
  if (profile.confidence == 'Low') {
    return TuneAvailability.lowConfidence;
  }
  // A plan that doesn't exist, or belongs to a DIFFERENT profile than the
  // one on screen, is never "ready" or "no correction needed" — both of
  // those claims require a real, matching plan to back them up.
  if (plan == null || plan.id != profile.tunePlanId) {
    return TuneAvailability.lowConfidence;
  }
  // `plan.bands.length` IS the real, deployable band count, not a proxy for
  // it: TunePlanner.generate() only ever appends a band to `bands` after it
  // survives every safety check (frequency/gain/Q bounds, spacing,
  // aggregate-cut limit — see TunePlanner._candidateRejection), and
  // TunePlan.validatePlan() (called at the end of generate(), and again by
  // TunePlanStore.save()) THROWS if any band has `safetyValidated == false`
  // or falls outside `safetyBounds` — so a `TunePlan` that made it into
  // storage at all can only ever contain bands that already passed Safety
  // Validator. TuneDeploymentPlan.fromTunePlan (the function _applyTune()
  // actually uses to build the real DSP write) maps every plan band 1:1 to
  // one deployment entry with no further filtering, so its output length is
  // always exactly `plan.bands.length` — there is no separate "deployable
  // count" to compute; this IS it.
  if (plan.bands.isEmpty) {
    return TuneAvailability.noCorrectionNeeded;
  }
  return TuneAvailability.readyToApply;
}
