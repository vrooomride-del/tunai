import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_plan.dart';

RoomMeasurement _measurement() {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    id: 'measurement-pref',
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
    peaks: const [
      ResonancePeak(frequency: 80, gain: -6, q: 4),
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
  group('SoundPreference', () {
    test('intensity never exceeds 1.0 for any preference', () {
      for (final preference in SoundPreference.values) {
        expect(preference.intensity, lessThanOrEqualTo(1.0));
        expect(preference.intensity, greaterThan(0.0));
      }
    });

    test('fromJson round-trips every value and falls back to balanced', () {
      for (final preference in SoundPreference.values) {
        expect(SoundPreference.fromJson(preference.toJson()), preference);
      }
      expect(SoundPreference.fromJson('not_a_real_preference'),
          SoundPreference.balanced);
      expect(SoundPreference.fromJson(null), SoundPreference.balanced);
    });

    test('label/description never mention technical terms', () {
      const banned = ['PEQ', 'DSP', 'dB', 'gain', 'EQ', 'frequency', 'Hz'];
      for (final preference in SoundPreference.values) {
        for (final ko in [true, false]) {
          final label = preference.label(ko: ko);
          final description = preference.description(ko: ko);
          for (final term in banned) {
            expect(label.toLowerCase(), isNot(contains(term.toLowerCase())));
            expect(
                description.toLowerCase(), isNot(contains(term.toLowerCase())));
          }
        }
      }
    });
  });

  group('TunePlanner + SoundPreference', () {
    test('balanced reproduces the exact unscaled default behavior', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final withoutPreference = planner.generate(_measurement());
      final withBalanced = planner.generate(
        _measurement(),
        preference: SoundPreference.balanced,
      );
      expect(withBalanced.id, withoutPreference.id);
      expect(withBalanced.bands.single.gainDb,
          withoutPreference.bands.single.gainDb);
    });

    test(
        'warm applies a gentler (smaller-magnitude) cut than balanced, '
        'for the exact same measured peak', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final balanced = planner.generate(_measurement());
      final warm = planner.generate(
        _measurement(),
        preference: SoundPreference.warm,
      );
      expect(warm.bands.single.gainDb.abs(),
          lessThan(balanced.bands.single.gainDb.abs()));
      expect(warm.bands.single.gainDb.abs(),
          closeTo(6 * SoundPreference.warm.intensity, 0.01));
    });

    test('a scaled-down preference still respects TuneSafetyBounds', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      for (final preference in SoundPreference.values) {
        final plan = planner.generate(_measurement(), preference: preference);
        for (final band in plan.bands) {
          expect(band.gainDb, lessThanOrEqualTo(0));
          expect(band.gainDb.abs(),
              lessThanOrEqualTo(plan.safetyBounds.maximumCutDb));
        }
      }
    });

    test(
        'different preferences for the same measurement do not collide '
        'on plan id', () {
      final planner = TunePlanner(now: () => DateTime.utc(2026, 7, 17));
      final ids = {
        for (final preference in SoundPreference.values)
          planner.generate(_measurement(), preference: preference).id,
      };
      expect(ids.length, SoundPreference.values.length);
    });
  });

  group('ConsumerSoundProfile.preference persistence', () {
    test('defaults to balanced and round-trips through JSON', () {
      final start = DateTime.utc(2026);
      final profile = ConsumerSoundProfile(
        id: 'p1',
        name: 'Test',
        roomType: 'Living Room',
        createdAt: start,
        updatedAt: start,
        micProfileName: 'Generic Phone Mic',
        confidence: 'High',
        isActive: false,
        status: ConsumerProfileStatus.ready,
        resultCards: const [],
        preference: SoundPreference.vocal,
      );
      expect(profile.preference, SoundPreference.vocal);

      final decoded = ConsumerSoundProfile.fromJson(profile.toJson());
      expect(decoded.preference, SoundPreference.vocal);
    });

    test('legacy JSON without a preference field defaults to balanced', () {
      final start = DateTime.utc(2026);
      final legacyJson = {
        'id': 'p1',
        'name': 'Test',
        'roomType': 'Living Room',
        'createdAt': start.toIso8601String(),
        'updatedAt': start.toIso8601String(),
        'micProfileName': 'Generic Phone Mic',
        'confidence': 'High',
        'isActive': false,
        'status': 'ready',
        'resultCards': [],
        // no 'preference' key at all — simulates data saved before this
        // field existed.
      };
      final decoded = ConsumerSoundProfile.fromJson(legacyJson);
      expect(decoded.preference, SoundPreference.balanced);
    });

    test('speakerProfileId defaults to null and round-trips through JSON',
        () {
      final start = DateTime.utc(2026);
      final profile = ConsumerSoundProfile(
        id: 'p1',
        name: 'Test',
        roomType: 'Living Room',
        createdAt: start,
        updatedAt: start,
        micProfileName: 'Generic Phone Mic',
        confidence: 'High',
        isActive: false,
        status: ConsumerProfileStatus.ready,
        resultCards: const [],
      );
      expect(profile.speakerProfileId, isNull);

      final withSpeaker = ConsumerSoundProfile(
        id: 'p2',
        name: 'Test',
        roomType: 'Living Room',
        createdAt: start,
        updatedAt: start,
        micProfileName: 'Generic Phone Mic',
        confidence: 'High',
        isActive: false,
        status: ConsumerProfileStatus.ready,
        resultCards: const [],
        speakerProfileId: 'tunai-one',
      );
      expect(withSpeaker.speakerProfileId, 'tunai-one');
      final decoded = ConsumerSoundProfile.fromJson(withSpeaker.toJson());
      expect(decoded.speakerProfileId, 'tunai-one');
    });
  });
}
