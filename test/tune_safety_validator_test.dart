import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/core/tune_safety_validator.dart';

TuneCorrectionBand _band({
  double frequencyHz = 120,
  double gainDb = -3,
  double q = 2,
  String evidenceReference = 'test:band',
}) =>
    TuneCorrectionBand(
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      evidenceReference: evidenceReference,
      safetyValidated: true,
    );

TunePlan _plan(List<TuneCorrectionBand> bands, {TuneSafetyBounds? bounds}) =>
    TunePlan(
      id: 'plan-1',
      sourceMeasurementId: 'measurement-1',
      createdAt: DateTime.utc(2026, 1, 1),
      bands: bands,
      rejectedCandidates: const [],
      safetyBounds: bounds ?? const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: 0.9,
      warnings: const [],
    );

void main() {
  group('TuneSafetyValidator — PASS cases', () {
    test('a normal, in-bounds TunePlan passes cleanly', () {
      final plan = _plan([
        _band(frequencyHz: 90, gainDb: -3, q: 3),
        _band(frequencyHz: 200, gainDb: -2, q: 4),
      ]);
      final result = const TuneSafetyValidator().validatePlan(plan);

      expect(result.passed, isTrue);
      expect(result.rejectedBands, isEmpty);
      expect(result.approvedBands, hasLength(2));
      expect(result.isDeployable, isTrue);
    });

    test('rebuild() produces a TunePlan usable by the existing Apply path', () {
      final plan = _plan([_band(frequencyHz: 90, gainDb: -3, q: 3)]);
      final result = const TuneSafetyValidator().validatePlan(plan);
      final rebuilt = result.rebuild(plan);

      expect(rebuilt.id, plan.id);
      expect(rebuilt.sourceMeasurementId, plan.sourceMeasurementId);
      expect(rebuilt.bands, result.approvedBands);
      expect(rebuilt.safetyBounds, plan.safetyBounds);
    });
  });

  group('TuneSafetyValidator — BLOCK cases (required)', () {
    test('gain exceeding maximumCutDb is blocked', () {
      const bounds = TuneSafetyBounds(maximumCutDb: 6);
      final plan = _plan(
        [_band(gainDb: -9)], // exceeds 6dB max cut
        bounds: bounds,
      );
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.approvedBands, isEmpty);
      expect(result.rejectedBands.single.reason, 'gain_exceeds_maximum_cut');
    });

    test('a boosted band is blocked when the bounds are cut-only', () {
      // maximumBoostDb defaults to 0 — the original Consumer policy, still
      // enforced for every caller that does not explicitly opt in.
      const bounds = TuneSafetyBounds();
      final plan = _plan([_band(gainDb: 3)], bounds: bounds);
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.rejectedBands.single.reason, 'not_supported_cut');
    });

    test('a boost beyond maximumBoostDb is blocked even when boost is allowed',
        () {
      // The full-range profile permits +3dB — the ceiling the deployment
      // executor itself accepts — and nothing above it.
      final plan = _plan([_band(gainDb: 4)],
          bounds: TuneSafetyBounds.consumerFullRange);
      final result = const TuneSafetyValidator(
              bounds: TuneSafetyBounds.consumerFullRange)
          .validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.rejectedBands.single.reason, 'gain_exceeds_maximum_boost');
    });

    test(
        'a boost within maximumBoostDb passes — broadband correction must be '
        'able to lift a region that measured below its neighbours', () {
      final plan = _plan([_band(gainDb: 3)],
          bounds: TuneSafetyBounds.consumerFullRange);
      final result = const TuneSafetyValidator(
              bounds: TuneSafetyBounds.consumerFullRange)
          .validatePlan(plan);

      expect(result.passed, isTrue);
      expect(result.approvedBands.single.gainDb, 3);
    });

    test('a boost never consumes the aggregate CUT budget', () {
      // That budget exists to stop a plan hollowing out the overall level by
      // stacking reductions; a boost does not contribute to that.
      final plan = _plan([
        _band(frequencyHz: 90, gainDb: -6),
        _band(frequencyHz: 300, gainDb: -6),
        _band(frequencyHz: 1000, gainDb: 3),
      ], bounds: TuneSafetyBounds.consumerFullRange);
      final result = const TuneSafetyValidator(
              bounds: TuneSafetyBounds.consumerFullRange)
          .validatePlan(plan);

      expect(result.approvedBands, hasLength(3));
      expect(result.rejectedBands, isEmpty);
    });

    test('frequency outside bounds is blocked', () {
      const bounds =
          TuneSafetyBounds(minimumFrequencyHz: 20, maximumFrequencyHz: 300);
      final plan = _plan([_band(frequencyHz: 5000)], bounds: bounds);
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.rejectedBands.single.reason, 'frequency_out_of_bounds');
    });

    test('Q below minimumQ is blocked', () {
      const bounds = TuneSafetyBounds(minimumQ: 0.7, maximumQ: 8);
      final plan = _plan([_band(q: 0.1)], bounds: bounds);
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.rejectedBands.single.reason, 'q_out_of_bounds');
    });

    test('Q above maximumQ is blocked', () {
      const bounds = TuneSafetyBounds(minimumQ: 0.7, maximumQ: 8);
      final plan = _plan([_band(q: 20)], bounds: bounds);
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.rejectedBands.single.reason, 'q_out_of_bounds');
    });

    test('a band beyond deployable band capacity is blocked', () {
      const capability = DspCapability(channel: 1, maxDeployableBands: 3);
      final plan = _plan([
        _band(frequencyHz: 60),
        _band(frequencyHz: 120),
        _band(frequencyHz: 220),
        _band(frequencyHz: 280), // 4th band — beyond capacity
      ]);
      final result =
          const TuneSafetyValidator(capability: capability).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.approvedBands, hasLength(3));
      expect(result.rejectedBands.single.reason, 'band_capacity_exceeded');
    });
  });

  group('TuneSafetyValidator — additional checks', () {
    test('aggregate cut over the limit is blocked once the sum tips over', () {
      const bounds = TuneSafetyBounds(
          aggregateCutLimitDb: 12, minimumSpacingHz: 0, minimumSpacingRatio: 0);
      final plan = _plan(
        [
          _band(frequencyHz: 60, gainDb: -5),
          _band(frequencyHz: 120, gainDb: -5),
          _band(frequencyHz: 220, gainDb: -5), // sum = 15 > 12
        ],
        bounds: bounds,
      );
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.approvedBands, hasLength(2));
      expect(result.rejectedBands.single.reason, 'aggregate_cut_limit');
    });

    test('bands spaced too closely together are blocked', () {
      const bounds =
          TuneSafetyBounds(minimumSpacingHz: 12, minimumSpacingRatio: 0.15);
      final plan = _plan(
        [
          _band(frequencyHz: 100),
          _band(frequencyHz: 104), // well inside the required spacing
        ],
        bounds: bounds,
      );
      final result =
          const TuneSafetyValidator(bounds: bounds).validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.approvedBands, hasLength(1));
      expect(result.rejectedBands.single.reason, 'overlapping_candidate');
    });

    test('non-finite values are blocked', () {
      final plan = _plan([_band(frequencyHz: double.nan)]);
      final result = const TuneSafetyValidator().validatePlan(plan);

      expect(result.passed, isFalse);
      expect(result.rejectedBands.single.reason, 'non_finite_candidate');
      expect(result.rejectedBands.single.frequencyHz, isNull);
    });

    test(
        'DspCapability (3 bands) is stricter than TuneSafetyBounds.maximumBands (4) by default — '
        'a plan that satisfies bounds alone is not automatically deployable',
        () {
      // TuneSafetyBounds.maximumBands defaults to 4, but the real ADAU1701
      // Consumer executor only accepts 3. This test locks in that the
      // validator enforces the smaller, real limit.
      final plan = _plan([
        _band(frequencyHz: 60),
        _band(frequencyHz: 120),
        _band(frequencyHz: 220),
        _band(frequencyHz: 280),
      ]);
      expect(
          plan.bands.length, lessThanOrEqualTo(plan.safetyBounds.maximumBands));

      final result = const TuneSafetyValidator().validatePlan(plan);
      expect(result.passed, isFalse);
      expect(result.approvedBands.length,
          DspCapability.consumerAdau1701.maxDeployableBands);
    });

    test('validate() accepts a raw band list, not just a TunePlan', () {
      final result = const TuneSafetyValidator().validate([
        _band(frequencyHz: 90, gainDb: -3, q: 3),
      ]);
      expect(result.passed, isTrue);
      expect(result.approvedBands, hasLength(1));
    });

    test('an empty proposal is a clean (trivial) pass with nothing to deploy',
        () {
      final result = const TuneSafetyValidator().validate(const []);
      expect(result.passed, isTrue);
      expect(result.isDeployable, isFalse);
    });
  });
}
