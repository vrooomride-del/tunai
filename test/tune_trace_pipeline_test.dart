// Traces the full responseBins → deviationBins → peak detection →
// TunePlanner pipeline to pin down where real measured deviation can fail
// to become a TunePlan band, without changing any of the pipeline's
// behavior (see the [TUNE_TRACE] debugPrint logging added alongside this
// test in audio_analyzer.dart/tune_plan.dart/measurement_controller.dart).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/core/fine_tune_adjustments.dart';

RoomMeasurement _measurementWithPeaks(List<ResonancePeak> peaks) {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    id: 'measurement-trace',
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
      FrequencyBin(frequency: 20, magnitude: -10),
      FrequencyBin(frequency: 500, magnitude: -10),
    ],
    peaks: peaks,
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
  group('AudioAnalyzer.detectPeaks search range', () {
    test(
        'a real, clearly-above-threshold bump at 400Hz (above the '
        '300Hz room-mode search ceiling) is never returned as a peak — '
        'documents the exact boundary a "graph shows bumps but bands=0" '
        'real-device report must be checked against', () {
      final bins = <FrequencyBin>[
        for (double f = 20; f <= 500; f += 0.67)
          FrequencyBin(
            frequency: f,
            // A genuine single-maximum bump (Gaussian, not a flat plateau —
            // detectPeaks' local-max check uses strict "no other bin in the
            // window is >=", so a perfectly flat top never qualifies)
            // centered at 400Hz, ~15dB above the floor — far above any
            // plausible 1.5dB local-max threshold.
            magnitude: 15 * math.exp(-0.5 * math.pow((f - 400) / 3, 2)),
          ),
      ];

      final peaks = AudioAnalyzer.detectPeaks(bins);

      expect(peaks, isEmpty,
          reason: 'detectPeaks only ever searches 20-300Hz '
              '(AudioAnalyzer.roomModeSearchCeilingHz) by design — a bump '
              'entirely above 300Hz can never become a peak, regardless of '
              'how large it is');
    });

    test('the identical bump shape at 120Hz (inside the search range) IS '
        'detected — confirms the 400Hz case above fails specifically '
        'because of frequency, not because the synthetic bins are somehow '
        'malformed', () {
      final bins = <FrequencyBin>[
        for (double f = 20; f <= 500; f += 0.67)
          FrequencyBin(
            frequency: f,
            magnitude: 15 * math.exp(-0.5 * math.pow((f - 120) / 3, 2)),
          ),
      ];

      final peaks = AudioAnalyzer.detectPeaks(bins);

      expect(peaks, isNotEmpty);
      expect(peaks.first.frequency, closeTo(120, 5));
    });
  });

  test(
      'TunePlanner.generate produces zero bands end-to-end when the '
      'measurement genuinely has zero detected peaks — never fabricates a '
      'band from nothing', () {
    final measurement = _measurementWithPeaks(const []);
    final plan = TunePlanner(now: () => DateTime.utc(2026, 7, 17))
        .generate(measurement, preference: SoundPreference.balanced);

    expect(plan.bands, isEmpty);
  });

  test(
      'TunePlanner.generate keeps a real peak within its safety bounds — '
      'a genuine, safely-correctable room issue always survives into '
      'plan.bands, confirming the pipeline is not silently zeroing out '
      'valid input', () {
    final measurement = _measurementWithPeaks(const [
      ResonancePeak(frequency: 120, gain: -6, q: 2),
    ]);
    final plan = TunePlanner(now: () => DateTime.utc(2026, 7, 17))
        .generate(measurement,
            preference: SoundPreference.balanced,
            fineTune: FineTuneAdjustments.neutral);

    expect(plan.bands, hasLength(1));
    expect(plan.bands.single.frequencyHz, 120);
  });
}
