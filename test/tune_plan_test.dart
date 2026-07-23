import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/core/tune_safety_validator.dart';

RoomMeasurement _measurement({
  CaptureQualityStatus quality = CaptureQualityStatus.valid,
  List<FrequencyBin>? bins,
  List<ResonancePeak>? peaks,
  int schemaVersion = roomMeasurementSchemaVersion,
}) {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    schemaVersion: schemaVersion,
    id: 'measurement-stage-2',
    roomType: 'Living Room',
    microphoneProfileId: 'Generic Phone Mic',
    hasMicrophoneCalibration: false,
    capturedAt: start,
    timing: CaptureTiming(
      requestedSampleRate: 44100,
      actualSampleRate: 44100,
      channelCount: 1,
      expectedDuration: const Duration(seconds: 10),
      capturedDuration: const Duration(seconds: 10),
      sampleCount: 441000,
      fileSizeBytes: 882044,
      recordingStartedAt: start,
      playbackStartedAt: start,
      playbackCompletedAt: start.add(const Duration(seconds: 10)),
      recordingStoppedAt: start.add(const Duration(seconds: 10)),
    ),
    usableRangeMinHz: 20,
    usableRangeMaxHz: 500,
    frequencyBins: bins ??
        const [
          FrequencyBin(frequency: 20, magnitude: -30),
          FrequencyBin(frequency: 80, magnitude: -17),
          FrequencyBin(frequency: 500, magnitude: -28),
        ],
    peaks: peaks ??
        const [
          ResonancePeak(frequency: 80, gain: -5, q: 4),
          ResonancePeak(frequency: 145, gain: -3, q: 3),
        ],
    consistencyMetric: 1,
    levels: const CaptureLevelMetrics(
      rms: 0.08,
      peakAbsolute: 0.3,
      estimatedNoiseFloorDbfs: null,
      clippingRatio: 0,
      signalPresent: true,
      severelyClipped: false,
    ),
    quality: quality,
    warnings: const [
      'No device-specific microphone calibration was available.'
    ],
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('invalid/cancelled, unsupported, and missing-spectrum inputs fail', () {
    final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
    expect(
        () => planner
            .generate(_measurement(quality: CaptureQualityStatus.invalid)),
        throwsStateError);
    expect(
        () => planner
            .generate(_measurement(quality: CaptureQualityStatus.cancelled)),
        throwsStateError);
    expect(() => planner.generate(_measurement(bins: const [])),
        throwsFormatException);
    expect(() => planner.generate(_measurement(schemaVersion: 999)),
        throwsFormatException);
    expect(
        () => planner.generate(_measurement(peaks: const [
              ResonancePeak(frequency: double.nan, gain: -2, q: 3),
            ])),
        throwsFormatException);
  });

  test(
      'a degraded-quality (lower confidence, but usable) measurement still '
      'produces a Tune — only invalid/cancelled are rejected', () {
    final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
    final plan =
        planner.generate(_measurement(quality: CaptureQualityStatus.degraded));
    expect(plan.bands, isNotEmpty);
    expect(plan.measurementQuality, CaptureQualityStatus.degraded);
  });

  test('valid measurement creates deterministic bounded cuts', () {
    final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
    final first = planner.generate(_measurement());
    final second = planner.generate(_measurement());

    expect(first.id, second.id);
    expect(first.bands.map((band) => band.toJson()),
        second.bands.map((band) => band.toJson()));
    expect(first.sourceMeasurementId, 'measurement-stage-2');
    expect(first.deploymentStatus, TuneDeploymentStatus.notDeployed);
    expect(first.bands, isNotEmpty);
    expect(
        first.bands.length, lessThanOrEqualTo(first.safetyBounds.maximumBands));
    expect(first.bands.every((band) => band.gainDb < 0), isTrue);
    expect(
        first.bands.every((band) =>
            band.frequencyHz >= first.safetyBounds.minimumFrequencyHz &&
            band.frequencyHz <= first.safetyBounds.maximumFrequencyHz &&
            band.gainDb >= -first.safetyBounds.maximumCutDb &&
            band.q >= first.safetyBounds.minimumQ &&
            band.q <= first.safetyBounds.maximumQ),
        isTrue);
    expect(first.bands.fold<double>(0, (sum, band) => sum + band.gainDb.abs()),
        lessThanOrEqualTo(first.safetyBounds.aggregateCutLimitDb));
  });

  test('duplicates, unsafe peaks, and excess bands are rejected with reasons',
      () {
    final plan = TunePlanner(now: () => DateTime.utc(2026)).generate(
      _measurement(peaks: const [
        ResonancePeak(frequency: 80, gain: -4, q: 4),
        ResonancePeak(frequency: 82, gain: -3, q: 4),
        ResonancePeak(frequency: 130, gain: 2, q: 4),
        // Physically meaningless Q — still rejected outright. A merely
        // *sharper-than-bounds* Q (e.g. 20) is NOT rejected any more; it is
        // clamped into bounds, covered by its own test below.
        ResonancePeak(frequency: 160, gain: -2, q: 0),
        ResonancePeak(frequency: 220, gain: -2, q: 3),
        ResonancePeak(frequency: 300, gain: -2, q: 3),
        ResonancePeak(frequency: 400, gain: -2, q: 3),
        ResonancePeak(frequency: 480, gain: -2, q: 3),
      ]),
    );
    final reasons = plan.rejectedCandidates.map((entry) => entry.reason);
    expect(reasons, contains('overlapping_candidate'));
    expect(reasons, contains('not_supported_cut'));
    expect(reasons, contains('q_out_of_bounds'));
    expect(plan.bands.length, lessThanOrEqualTo(4));
  });

  test(
      'sharp real room modes (Q saturated at the analyzer ceiling) still '
      'produce deployable bands — real-hardware regression', () {
    // Verbatim from a real Room Scan on a SM-G981N: every detected peak came
    // back at AudioAnalyzer.maxEstimatedQ (16.0), because at Room Scan's FFT
    // bin resolution a genuinely sharp room mode spans only 1-2 bins. The
    // planner's Q bounds are [0.7, 8], so the candidate gate used to reject
    // all four as `q_out_of_bounds` and emit a ZERO-band plan — which the UI
    // correctly reported as "no adjustment needed", leaving no Apply path and
    // therefore no Original/TUNAI comparison, from a perfectly valid capture.
    const analyzerCeilingQ = AudioAnalyzer.maxEstimatedQ;
    final plan = TunePlanner(now: () => DateTime.utc(2026)).generate(
      _measurement(peaks: const [
        ResonancePeak(frequency: 278.6, gain: -18.6, q: analyzerCeilingQ),
        ResonancePeak(frequency: 233.5, gain: -12.5, q: analyzerCeilingQ),
        ResonancePeak(frequency: 196.5, gain: -9.5, q: analyzerCeilingQ),
        ResonancePeak(frequency: 70.7, gain: -8.3, q: analyzerCeilingQ),
      ]),
    );

    expect(plan.bands, isNotEmpty,
        reason: 'a valid measurement must not yield a zero-band plan');
    expect(
      plan.rejectedCandidates.map((entry) => entry.reason),
      isNot(contains('q_out_of_bounds')),
    );
    // Safety is preserved by clamping, not by discarding: every emitted band
    // still carries a Q inside the planner's own bounds.
    for (final band in plan.bands) {
      expect(band.q, greaterThanOrEqualTo(plan.safetyBounds.minimumQ));
      expect(band.q, lessThanOrEqualTo(plan.safetyBounds.maximumQ));
    }
  });

  test(
      'a tonally unbalanced room produces broadband corrections across the '
      'full range — not only room modes below 300Hz', () {
    // A broad 8dB excess centred at 3kHz: nothing AudioAnalyzer.detectPeaks
    // could ever act on (it stops at 300Hz), and exactly the kind of
    // imbalance a listener hears most.
    final bins = <FrequencyBin>[];
    for (var f = 20.0; f <= 10000; f *= 1.002) {
      final octaves = math.log(f / 3000) / math.ln2;
      bins.add(FrequencyBin(
        frequency: f,
        magnitude: -70 + 8 * math.exp(-(octaves * octaves) / (2 * 0.25)),
      ));
    }

    final plan = TunePlanner(now: () => DateTime.utc(2026))
        .generate(_measurement(bins: bins, peaks: const []));

    expect(plan.bands, isNotEmpty);
    expect(
      plan.bands.any((b) =>
          b.source == TuneCorrectionSource.tonalBalance &&
          b.frequencyHz > 1500),
      isTrue,
      reason: 'the 3kHz imbalance must be corrected',
    );
    // Everything still inside the bounds the deployment path enforces.
    for (final band in plan.bands) {
      expect(band.gainDb, greaterThanOrEqualTo(-plan.safetyBounds.maximumCutDb));
      expect(band.gainDb, lessThanOrEqualTo(plan.safetyBounds.maximumBoostDb));
      expect(band.q, greaterThanOrEqualTo(plan.safetyBounds.minimumQ));
      expect(band.q, lessThanOrEqualTo(plan.safetyBounds.maximumQ));
    }
    // And still deployable on the real 3-band hardware.
    expect(
      const TuneSafetyValidator().validatePlan(plan).approvedBands,
      isNotEmpty,
    );
  });

  test('TunePlan persistence is versioned and corruption-safe', () async {
    final plan =
        TunePlanner(now: () => DateTime.utc(2026)).generate(_measurement());
    await TunePlanStore.save(plan);
    final restored = await TunePlanStore.load();
    expect(restored?.id, plan.id);
    expect(restored?.deploymentStatus, TuneDeploymentStatus.notDeployed);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tunai_current_tune_plan_v1', '{broken');
    expect(await TunePlanStore.load(), isNull);
  });

  test('generated profile links measurement and plan without applied state',
      () async {
    final plan =
        TunePlanner(now: () => DateTime.utc(2026)).generate(_measurement());
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.upsertGeneratedAndSelect(ConsumerSoundProfile(
      id: plan.id,
      name: 'Living Room Acoustic Tune',
      roomType: 'Living Room',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      micProfileName: 'Generic Phone Mic',
      confidence: 'High',
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: const [],
      measurementId: plan.sourceMeasurementId,
      tunePlanId: plan.id,
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    ));

    final profile = notifier.state.single;
    expect(profile.measurementId, plan.sourceMeasurementId);
    expect(profile.tunePlanId, plan.id);
    expect(profile.isSelected, isTrue);
    expect(profile.isActive, isFalse);
    expect(profile.deploymentStatus, TuneDeploymentStatus.notDeployed);

    final recreated = ConsumerSoundProfileNotifier();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(recreated.state.single.tunePlanId, plan.id);
    expect(recreated.state.single.isActive, isFalse);
  });

  test(
      'real TUNE flow contains no fixed delay, and Sound Score comes from '
      'real computation, not a fabricated/hardcoded value', () {
    final source = File('lib/features/ai/ai_screen.dart').readAsStringSync();
    expect(source, isNot(contains('Duration(milliseconds: 2600)')));
    // soundScoreBefore/After are legitimately wired now (Before/After Sound
    // Experience) — the guard is that they trace back to a real calculator
    // call on real curves, never a literal number.
    expect(source, contains('soundScoreBefore: beforeScore?.total'));
    expect(source, contains('soundScoreAfter: afterScore?.total'));
    expect(source,
        contains('SoundScoreCalculator.compute(measurement.frequencyBins)'));
    expect(source, isNot(matches(RegExp(r'soundScoreBefore:\s*\d'))));
    expect(source, isNot(matches(RegExp(r'soundScoreAfter:\s*\d'))));
    expect(source, contains('TunePlanner'));
    expect(source, contains('RoomMeasurementStore.load'));
    expect(source, contains('TuneDeploymentStatus.notDeployed'));
  });
}
