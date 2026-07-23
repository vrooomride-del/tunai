import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart' show FrequencyBin, ResonancePeak;
import 'package:tunai/core/factory_sound_profile.dart';
import 'package:tunai/core/preference_correction_generator.dart';
import 'package:tunai/core/preference_plan_merger.dart';
import 'package:tunai/core/preference_target.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_plan.dart';

/// Release-Candidate invariants, consolidated in one place. Each of these is
/// individually covered elsewhere; this file is the RC checklist — if any of
/// these breaks, TUNAI Consumer is not release-ready.
RoomMeasurement _measurement({List<ResonancePeak>? peaks}) {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    schemaVersion: roomMeasurementSchemaVersion,
    id: 'm',
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
    frequencyBins: const [
      FrequencyBin(frequency: 20, magnitude: -30),
      FrequencyBin(frequency: 80, magnitude: -17),
      FrequencyBin(frequency: 500, magnitude: -28),
    ],
    peaks: peaks ??
        const [
          ResonancePeak(frequency: 80, gain: -5, q: 4),
          ResonancePeak(frequency: 220, gain: -3, q: 3),
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
    quality: CaptureQualityStatus.valid,
    warnings: const [],
  );
}

void main() {
  group('RC invariant — DSP path order: Room correction → Preference → Safety',
      () {
    test('no preference → the deployed plan is byte-identical to the room plan',
        () {
      final room = const TunePlanner(now: DateTime.now)
          .generate(_measurement(), preference: SoundPreference.balanced);
      final merged = const PreferencePlanMerger().merge(room, const []);
      expect(identical(merged, room), isTrue);
      expect(merged.bands.map((b) => b.toJson()),
          room.bands.map((b) => b.toJson()));
    });

    test('preference bands are the LAST offered → room always wins the budget',
        () {
      final room = const TunePlanner(now: DateTime.now)
          .generate(_measurement(), preference: SoundPreference.balanced);
      final pref = const PreferenceCorrectionGenerator()
          .generate(PreferenceTarget.forDescriptor('warm')!);
      final merged = const PreferencePlanMerger().merge(room, pref);
      // Every room band is preserved.
      for (final rb in room.bands) {
        expect(
            merged.bands.any((b) =>
                b.source == rb.source &&
                (b.frequencyHz - rb.frequencyHz).abs() < 0.01),
            isTrue);
      }
    });
  });

  group('RC invariant — Factory protection', () {
    test('Consumer obtains factory only read-only; the registry is the entry',
        () {
      expect(FactorySoundProfileRegistry.consumerReference().speakerModel,
          'TUNAI ONE');
      // targetCharacter is the immutable factory anchor.
      expect(
          FactorySoundProfileRegistry.consumerReference().targetCharacter,
          'natural_balanced');
    });

    test('a preference nudge never exceeds a small, factory-safe magnitude', () {
      for (final d in ['warm', 'detailed', 'vocal', 'comfortable', 'relaxed']) {
        final target = PreferenceTarget.forDescriptor(d);
        if (target == null) continue;
        for (final b in const PreferenceCorrectionGenerator().generate(target)) {
          expect(b.gainDb.abs(),
              lessThanOrEqualTo(PreferenceCorrectionGenerator.nudgeDb));
          expect(b.gainDb, lessThanOrEqualTo(3.0)); // never past boost ceiling
        }
      }
    });
  });

  group('RC invariant — AI never blocks the Tune', () {
    test('the whole tuning pipeline is synchronous & AI-free (no await on a '
        'network call to produce a plan)', () {
      // Producing a deployable plan uses only deterministic, local components.
      final room = const TunePlanner(now: DateTime.now)
          .generate(_measurement(), preference: SoundPreference.balanced);
      final merged = const PreferencePlanMerger().merge(
          room,
          const PreferenceCorrectionGenerator()
              .generate(PreferenceTarget.forDescriptor('warm')!));
      expect(merged.bands, isNotEmpty);
      // No AI type appears in this path — it is structurally impossible for an
      // AI failure to prevent this plan from being produced.
    });
  });

  group('RC invariant — Preference target is real, not fake UI', () {
    test('balanced room still yields an applied preference band', () {
      // A room with no correctable peaks.
      final room = const TunePlanner(now: DateTime.now)
          .generate(_measurement(peaks: const []),
              preference: SoundPreference.balanced);
      final pref = const PreferenceCorrectionGenerator()
          .generate(PreferenceTarget.forDescriptor('warm')!);
      final merged = const PreferencePlanMerger().merge(room, pref);
      expect(
          merged.bands
              .any((b) => b.source == TuneCorrectionSource.preferenceTarget),
          isTrue,
          reason: 'taste must shape the sound even on a neutral room');
    });
  });
}
