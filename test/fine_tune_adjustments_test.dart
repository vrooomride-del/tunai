import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/fine_tune_adjustments.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_plan.dart';

RoomMeasurement _measurement({List<ResonancePeak>? peaks}) {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    id: 'measurement-fine-tune',
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
    // 80Hz = low/sub-bass band; 200Hz = upper-bass/"boxy" band.
    peaks: peaks ??
        const [
          ResonancePeak(frequency: 80, gain: -5, q: 4),
          ResonancePeak(frequency: 200, gain: -4, q: 3),
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

TuneCorrectionBand _bandAt(TunePlan plan, double frequencyHz) =>
    plan.bands.firstWhere((b) => b.frequencyHz == frequencyHz);

void main() {
  group('SoundPreference directional weighting', () {
    test('warm eases the low band more than the mid/boxy band', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final balanced = planner.generate(_measurement());
      final warm = planner.generate(_measurement(), preference: SoundPreference.warm);

      final balancedLow = _bandAt(balanced, 80).gainDb.abs();
      final balancedMid = _bandAt(balanced, 200).gainDb.abs();
      final warmLow = _bandAt(warm, 80).gainDb.abs();
      final warmMid = _bandAt(warm, 200).gainDb.abs();

      expect(warmLow, lessThan(balancedLow));
      expect(warmMid, lessThan(balancedMid));
      // The real, directional claim: warm eases the low band proportionally
      // more than the mid band (keeps bass fullness, still cleans up mud).
      expect(warmLow / balancedLow, lessThan(warmMid / balancedMid));
    });

    test('vocal eases the mid band more than the low band', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final balanced = planner.generate(_measurement());
      final vocal = planner.generate(_measurement(), preference: SoundPreference.vocal);

      final balancedLow = _bandAt(balanced, 80).gainDb.abs();
      final balancedMid = _bandAt(balanced, 200).gainDb.abs();
      final vocalLow = _bandAt(vocal, 80).gainDb.abs();
      final vocalMid = _bandAt(vocal, 200).gainDb.abs();

      // Vocal stays fully assertive on the low-frequency masking band...
      expect(vocalLow, closeTo(balancedLow, 0.01));
      // ...but eases the mid band relative to balanced.
      expect(vocalMid, lessThan(balancedMid));
    });

    test('weightFor selects intensity below the threshold, midBandFactor at/above it', () {
      for (final preference in SoundPreference.values) {
        expect(preference.weightFor(SoundPreference.midBandThresholdHz - 1),
            preference.intensity);
        expect(preference.weightFor(SoundPreference.midBandThresholdHz),
            preference.midBandFactor);
      }
    });
  });

  group('FineTuneAdjustments + TunePlanner', () {
    test('neutral Fine Tune reproduces the exact preference-only plan', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final withoutFineTune = planner.generate(_measurement(), preference: SoundPreference.warm);
      final withNeutral = planner.generate(
        _measurement(),
        preference: SoundPreference.warm,
        fineTune: FineTuneAdjustments.neutral,
      );
      expect(withNeutral.id, withoutFineTune.id);
      expect(withNeutral.bands.length, withoutFineTune.bands.length);
      for (var i = 0; i < withNeutral.bands.length; i++) {
        expect(withNeutral.bands[i].gainDb, withoutFineTune.bands[i].gainDb);
        expect(withNeutral.bands[i].q, withoutFineTune.bands[i].q);
      }
    });

    test('bassWeight only affects the low band, warmWeight only the mid band', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final base = planner.generate(_measurement());

      final bassOnly = planner.generate(
        _measurement(),
        fineTune: const FineTuneAdjustments(bassWeight: 0.5),
      );
      expect(_bandAt(bassOnly, 80).gainDb.abs(),
          closeTo(_bandAt(base, 80).gainDb.abs() * 0.5, 0.01));
      expect(_bandAt(bassOnly, 200).gainDb.abs(),
          closeTo(_bandAt(base, 200).gainDb.abs(), 0.01));

      final warmOnly = planner.generate(
        _measurement(),
        fineTune: const FineTuneAdjustments(warmWeight: 0.5),
      );
      expect(_bandAt(warmOnly, 80).gainDb.abs(),
          closeTo(_bandAt(base, 80).gainDb.abs(), 0.01));
      expect(_bandAt(warmOnly, 200).gainDb.abs(),
          closeTo(_bandAt(base, 200).gainDb.abs() * 0.5, 0.01));
    });

    test('vocalWeight scales both bands together', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final base = planner.generate(_measurement());
      final scaled = planner.generate(
        _measurement(),
        fineTune: const FineTuneAdjustments(vocalWeight: 0.4),
      );
      expect(_bandAt(scaled, 80).gainDb.abs(),
          closeTo(_bandAt(base, 80).gainDb.abs() * 0.4, 0.01));
      expect(_bandAt(scaled, 200).gainDb.abs(),
          closeTo(_bandAt(base, 200).gainDb.abs() * 0.4, 0.01));
    });

    test('spaceWeight blends Q toward the room-measured value, never past it', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      const bounds = TuneSafetyBounds();
      final base = planner.generate(_measurement());
      final broad = planner.generate(
        _measurement(),
        fineTune: const FineTuneAdjustments(spaceWeight: 0.0),
      );
      final precise = planner.generate(
        _measurement(),
        fineTune: const FineTuneAdjustments(spaceWeight: 1.0),
      );

      // spaceWeight=0 → broadest allowed Q (minimumQ).
      expect(_bandAt(broad, 80).q, closeTo(bounds.minimumQ, 0.01));
      // spaceWeight=1 → exactly the room's own measured/clamped Q, same as
      // the default (unchanged) behavior.
      expect(_bandAt(precise, 80).q, closeTo(_bandAt(base, 80).q, 0.01));
      // Never sharper (higher) than the real measured Q.
      expect(_bandAt(broad, 80).q, lessThanOrEqualTo(_bandAt(base, 80).q));
    });

    test('detailBandLimit keeps only the most significant bands', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final limited = planner.generate(
        _measurement(),
        fineTune: const FineTuneAdjustments(detailBandLimit: 1),
      );
      expect(limited.bands.length, 1);
      // The 80Hz peak has the larger cut (-5 vs -4), so it's the one kept.
      expect(limited.bands.single.frequencyHz, 80);
      expect(
          limited.rejectedCandidates
              .any((r) => r.reason == 'fine_tune_detail_limit'),
          isTrue);
    });

    test('detailBandLimit is capped at the real deployable capacity (3)', () {
      expect(FineTuneAdjustments.maxDetailBandLimit, 3);
      expect(
        () => FineTuneAdjustments(detailBandLimit: 4),
        throwsA(isA<AssertionError>()),
      );
    });

    test('Fine Tune never exceeds TuneSafetyBounds regardless of settings', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      const bounds = TuneSafetyBounds();
      for (final preference in SoundPreference.values) {
        for (final adjustments in [
          FineTuneAdjustments.neutral,
          const FineTuneAdjustments(bassWeight: 0.1, warmWeight: 0.1),
          const FineTuneAdjustments(spaceWeight: 0.0, detailBandLimit: 1),
          const FineTuneAdjustments(
              bassWeight: 1, warmWeight: 1, vocalWeight: 1, spaceWeight: 1, detailBandLimit: 3),
        ]) {
          final plan = planner.generate(_measurement(),
              preference: preference, fineTune: adjustments);
          for (final band in plan.bands) {
            expect(band.gainDb, lessThanOrEqualTo(0));
            expect(band.gainDb.abs(), lessThanOrEqualTo(bounds.maximumCutDb));
            expect(band.q, greaterThanOrEqualTo(bounds.minimumQ));
            expect(band.q, lessThanOrEqualTo(bounds.maximumQ));
          }
        }
      }
    });
  });

  group('TuneCorrectionBand.source', () {
    test('defaults to roomMode and round-trips through JSON', () {
      const band = TuneCorrectionBand(
        frequencyHz: 100,
        gainDb: -3,
        q: 2,
        evidenceReference: 'test:100.0',
        safetyValidated: true,
      );
      expect(band.source, TuneCorrectionSource.roomMode);
      final decoded = TuneCorrectionBand.fromJson(band.toJson());
      expect(decoded.source, TuneCorrectionSource.roomMode);
    });

    test('legacy JSON without a source field defaults to roomMode', () {
      final legacy = {
        'frequencyHz': 100.0,
        'gainDb': -3.0,
        'q': 2.0,
        'evidenceReference': 'test:100.0',
        'safetyValidated': true,
      };
      expect(TuneCorrectionBand.fromJson(legacy).source,
          TuneCorrectionSource.roomMode);
    });

    test('speakerCharacter round-trips explicitly', () {
      const band = TuneCorrectionBand(
        frequencyHz: 100,
        gainDb: -3,
        q: 2,
        evidenceReference: 'test:100.0',
        safetyValidated: true,
        source: TuneCorrectionSource.speakerCharacter,
      );
      final decoded = TuneCorrectionBand.fromJson(band.toJson());
      expect(decoded.source, TuneCorrectionSource.speakerCharacter);
    });
  });
}
