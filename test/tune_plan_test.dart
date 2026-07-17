import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/tune_plan.dart';

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

  test('invalid, low-quality, unsupported, and missing-spectrum inputs fail',
      () {
    final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
    expect(
        () => planner
            .generate(_measurement(quality: CaptureQualityStatus.invalid)),
        throwsStateError);
    expect(
        () => planner
            .generate(_measurement(quality: CaptureQualityStatus.degraded)),
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
        ResonancePeak(frequency: 160, gain: -2, q: 20),
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

  test('real TUNE flow contains no fixed delay or fabricated score source', () {
    final source = File('lib/features/ai/ai_screen.dart').readAsStringSync();
    expect(source, isNot(contains('Duration(milliseconds: 2600)')));
    expect(source, isNot(contains('soundScoreBefore:')));
    expect(source, isNot(contains('soundScoreAfter:')));
    expect(source, contains('TunePlanner'));
    expect(source, contains('RoomMeasurementStore.load'));
    expect(source, contains('TuneDeploymentStatus.notDeployed'));
  });
}
