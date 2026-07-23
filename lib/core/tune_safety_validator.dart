import 'dart:math' as math;

import 'tune_plan.dart';

/// Describes what the current DSP deployment path can actually execute —
/// distinct from [TuneSafetyBounds], which describes what is acoustically
/// safe to *propose*. A band can be acoustically safe and still be
/// undeployable (e.g. more bands than the hardware/executor accepts).
///
/// Kept in sync by hand with `ConsumerDspDeploymentExecutor`
/// (`lib/core/consumer_dsp_deployment.dart`): channel must equal
/// `ConsumerDspDeploymentExecutor.confirmedTunePlanChannel`, and the executor
/// rejects any plan with more than 3 bands (`bandId` 0–2) as `tooManyBands`.
/// Not imported directly from the executor to avoid a `core → features`
/// dependency; test coverage on both sides keeps the two from silently
/// drifting apart.
class DspCapability {
  final int channel;
  final int maxDeployableBands;

  const DspCapability({
    required this.channel,
    required this.maxDeployableBands,
  });

  /// The real, currently-deployable capability for TUNAI ONE / Consumer
  /// over ICP5 BLE → ADAU1701.
  ///
  /// NOTE: [TuneSafetyBounds.maximumBands] defaults to 4, but
  /// `ConsumerDspDeploymentExecutor` only accepts up to 3 bands (bandId
  /// 0–2). A plan that passes `TuneSafetyBounds` alone is not guaranteed to
  /// be deployable — this validator enforces the smaller, real limit so a
  /// PASS here is always actually deployable without a separate Apply-time
  /// surprise.
  static const consumerAdau1701 = DspCapability(
    channel: 1,
    maxDeployableBands: 3,
  );
}

/// Result of running [TuneSafetyValidator.validate] / `.validatePlan`.
///
/// FAIL never means "clamped to fit" — a rejected band is dropped, not
/// silently adjusted. [approvedBands] only ever contains bands unchanged
/// from what was proposed.
class ValidatedTunePlan {
  final List<TuneCorrectionBand> approvedBands;
  final List<RejectedTuneCandidate> rejectedBands;

  /// True only if every proposed band was approved unchanged — the "clean
  /// PASS" case. Any rejection (even a partial one) makes this false, even
  /// though [approvedBands] may still be non-empty and deployable.
  final bool passed;

  const ValidatedTunePlan({
    required this.approvedBands,
    required this.rejectedBands,
    required this.passed,
  });

  /// Whether there is anything safe left to send to DSP Apply at all.
  bool get isDeployable => approvedBands.isNotEmpty;

  /// Rebuilds a full [TunePlan] from [source] with `bands` replaced by only
  /// [approvedBands] (any new rejections appended to `rejectedCandidates`),
  /// so it can flow into the existing Apply path
  /// (`TuneDeploymentPlan.fromTunePlan`) completely unchanged.
  TunePlan rebuild(TunePlan source) => TunePlan(
        schemaVersion: source.schemaVersion,
        id: source.id,
        sourceMeasurementId: source.sourceMeasurementId,
        algorithmVersion: source.algorithmVersion,
        createdAt: source.createdAt,
        bands: List.unmodifiable(approvedBands),
        rejectedCandidates: List.unmodifiable([
          ...source.rejectedCandidates,
          ...rejectedBands,
        ]),
        safetyBounds: source.safetyBounds,
        measurementQuality: source.measurementQuality,
        measurementConsistency: source.measurementConsistency,
        warnings: source.warnings,
        deploymentStatus: source.deploymentStatus,
      );
}

/// TUNAI's Safety Validator — the single checkpoint every proposed PEQ band
/// set must pass before it may reach DSP Apply, regardless of where it came
/// from (today: the local, deterministic [TunePlanner]; in the future: an
/// AI recommendation converted to [TuneCorrectionBand]s).
///
/// "AI interprets. TUNAI validates. DSP executes." This class is the
/// "TUNAI validates" step: it never trusts frequency/gain/Q values from any
/// source, re-checks every band from scratch against [TuneSafetyBounds] and
/// [DspCapability], and never mutates a value to make it pass — an
/// out-of-bounds band is rejected, not clamped.
///
/// This does not replace or modify existing safety code:
/// - [TunePlanner.generate] still does its own inline filtering during local
///   candidate generation (unchanged).
/// - [TunePlanner.validatePlan] still does its own throw-based integrity
///   check on save/load (unchanged).
/// - `ConsumerDspDeploymentExecutor`'s own guard at write-time is unchanged
///   and remains the final safety net regardless of what this validator
///   decided.
///
/// This class is the new, explicit checkpoint positioned *before* those:
/// somewhere that can evaluate a band proposal from any source — including
/// one that never went through [TunePlanner] at all — and decide, band by
/// band, what is safe to keep.
class TuneSafetyValidator {
  final TuneSafetyBounds bounds;
  final DspCapability capability;

  const TuneSafetyValidator({
    this.bounds = TuneSafetyBounds.consumerFullRange,
    this.capability = DspCapability.consumerAdau1701,
  });

  /// Validates an already-built [TunePlan]'s bands. Useful both for the
  /// existing local `TunePlanner` output (defense-in-depth re-check against
  /// real deployment capability) and, later, for a `TunePlan`-shaped AI
  /// recommendation.
  ValidatedTunePlan validatePlan(TunePlan plan) => validate(plan.bands);

  /// Validates a raw list of proposed bands from any source. Order is
  /// preserved among approved bands.
  ValidatedTunePlan validate(List<TuneCorrectionBand> proposedBands) {
    final approved = <TuneCorrectionBand>[];
    final rejected = <RejectedTuneCandidate>[];
    var aggregateCut = 0.0;

    for (final band in proposedBands) {
      final reason = _reject(band, approved, aggregateCut);
      if (reason != null) {
        rejected.add(RejectedTuneCandidate(
          frequencyHz: band.frequencyHz.isFinite ? band.frequencyHz : null,
          reason: reason,
        ));
        continue;
      }
      approved.add(band);
      // Cuts only — mirrors the budget check in `_reject`.
      if (band.gainDb < 0) aggregateCut += band.gainDb.abs();
    }

    return ValidatedTunePlan(
      approvedBands: List.unmodifiable(approved),
      rejectedBands: List.unmodifiable(rejected),
      passed: rejected.isEmpty,
    );
  }

  /// Reason codes reuse `TunePlanner._candidateRejection`'s vocabulary where
  /// the check is equivalent (`frequency_out_of_bounds`, `not_supported_cut`,
  /// `q_out_of_bounds`, `overlapping_candidate`, `aggregate_cut_limit`,
  /// `non_finite_candidate`), so a rejection means the same thing regardless
  /// of which layer produced it. Two are new here because this validator's
  /// behavior deliberately differs from `TunePlanner.generate`, which
  /// silently *clamps* an oversized cut to `maximumCutDb` instead of
  /// rejecting it — this validator never mutates a value to make it pass, so
  /// an oversized cut is `gain_exceeds_maximum_cut` (rejected), and a band
  /// beyond real deployment capacity is `band_capacity_exceeded`.
  String? _reject(
    TuneCorrectionBand band,
    List<TuneCorrectionBand> approvedSoFar,
    double aggregateCutSoFar,
  ) {
    if (!band.frequencyHz.isFinite ||
        !band.gainDb.isFinite ||
        !band.q.isFinite) {
      return 'non_finite_candidate';
    }
    if (band.frequencyHz < bounds.minimumFrequencyHz ||
        band.frequencyHz > bounds.maximumFrequencyHz) {
      return 'frequency_out_of_bounds';
    }
    // Cut-only unless the bounds explicitly permit boost. `maximumBoostDb`
    // defaults to 0, so the historical cut-only policy is unchanged for every
    // caller that does not opt in; broadband tonal correction opts in with
    // the ceiling the deployment executor itself accepts (+3dB).
    if (band.gainDb.abs() < 1) return 'not_supported_cut';
    if (band.gainDb > bounds.maximumBoostDb) {
      return bounds.maximumBoostDb <= 0
          ? 'not_supported_cut'
          : 'gain_exceeds_maximum_boost';
    }
    if (band.gainDb < 0 && band.gainDb.abs() > bounds.maximumCutDb) {
      return 'gain_exceeds_maximum_cut';
    }
    if (band.q < bounds.minimumQ || band.q > bounds.maximumQ) {
      return 'q_out_of_bounds';
    }
    if (approvedSoFar.length >= capability.maxDeployableBands) {
      return 'band_capacity_exceeded';
    }
    for (final other in approvedSoFar) {
      final requiredSpacing = math.max(
        bounds.minimumSpacingHz,
        math.min(other.frequencyHz, band.frequencyHz) *
            bounds.minimumSpacingRatio,
      );
      if ((other.frequencyHz - band.frequencyHz).abs() < requiredSpacing) {
        return 'overlapping_candidate';
      }
    }
    // Only CUTS accumulate against this budget. It exists to stop a plan
    // hollowing out the overall level by stacking reductions; a boost does
    // not contribute to that, and is separately bounded per-band above.
    if (band.gainDb < 0 &&
        aggregateCutSoFar + band.gainDb.abs() > bounds.aggregateCutLimitDb) {
      return 'aggregate_cut_limit';
    }
    return null;
  }
}
