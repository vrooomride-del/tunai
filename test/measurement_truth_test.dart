import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/measurement_capture_sequence.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/room_scan_result.dart';

void main() {
  group('MeasurementCaptureSequence', () {
    test('recorder starts before playback and stops at playback completion',
        () async {
      final events = <String>[];
      var tick = 0;
      final base = DateTime.utc(2026, 7, 17);
      final sequence = MeasurementCaptureSequence(
        now: () => base.add(Duration(seconds: tick++)),
      );

      final timing = await sequence.run(
        startRecorder: () async => events.add('recorder-start'),
        recorderIsReady: () => true,
        playSignalToCompletion: () async {
          events.add('playback-start');
          events.add('playback-complete');
        },
        stopRecorder: () async => events.add('recorder-stop'),
        stopPlayback: () async => events.add('playback-stop'),
      );

      expect(events, [
        'recorder-start',
        'playback-start',
        'playback-complete',
        'recorder-stop',
        'playback-stop',
      ]);
      expect(timing.recordingStartedAt, base);
      expect(
          timing.recordingStoppedAt,
          timing.playbackCompletedAt.add(
            const Duration(seconds: 1),
          ));
    });

    test('recorder readiness failure blocks playback', () async {
      var playbackStarted = false;
      const sequence = MeasurementCaptureSequence(now: DateTime.now);
      await expectLater(
        sequence.run(
          startRecorder: () async {},
          recorderIsReady: () => false,
          playSignalToCompletion: () async => playbackStarted = true,
          stopRecorder: () async {},
          stopPlayback: () async {},
        ),
        throwsStateError,
      );
      expect(playbackStarted, isFalse);
    });

    test('playback failure prevents a successful capture sequence', () async {
      const sequence = MeasurementCaptureSequence(now: DateTime.now);
      await expectLater(
        sequence.run(
          startRecorder: () async {},
          recorderIsReady: () => true,
          playSignalToCompletion: () => Future<void>.error(
            StateError('playback failed'),
          ),
          stopRecorder: () async {},
          stopPlayback: () async {},
        ),
        throwsStateError,
      );
    });
  });

  group('RoomMeasurementValidator', () {
    CaptureTiming timing({
      int samples = 441000,
      Duration captured = const Duration(seconds: 10),
      int fileSize = 882044,
    }) {
      final start = DateTime.utc(2026, 7, 17);
      return CaptureTiming(
        requestedSampleRate: 44100,
        actualSampleRate: 44100,
        channelCount: 1,
        expectedDuration: const Duration(seconds: 10),
        capturedDuration: captured,
        sampleCount: samples,
        fileSizeBytes: fileSize,
        recordingStartedAt: start,
        playbackStartedAt: start,
        playbackCompletedAt: start.add(const Duration(seconds: 10)),
        recordingStoppedAt: start.add(const Duration(seconds: 10)),
      );
    }

    const bins = [
      FrequencyBin(frequency: 20, magnitude: -30),
      FrequencyBin(frequency: 100, magnitude: -20),
      FrequencyBin(frequency: 500, magnitude: -25),
    ];
    const peaks = [
      ResonancePeak(frequency: 100, gain: -4, q: 4),
    ];

    test('zero-length and too-short captures are rejected', () {
      final emptyLevels = RoomMeasurementValidator.calculateLevels(const []);
      expect(
        RoomMeasurementValidator.validate(
          timing: timing(samples: 0, fileSize: 44, captured: Duration.zero),
          samples: const [],
          bins: const [],
          peaks: const [],
          levels: emptyLevels,
        ),
        isNotEmpty,
      );

      final short = List<double>.filled(44100, 0.1);
      expect(
        RoomMeasurementValidator.validate(
          timing: timing(
            samples: short.length,
            captured: const Duration(seconds: 1),
          ),
          samples: short,
          bins: bins,
          peaks: peaks,
          levels: RoomMeasurementValidator.calculateLevels(short),
        ),
        isNotEmpty,
      );
    });

    test('near-silence and severe clipping are rejected', () {
      final silence = List<double>.filled(441000, 0.00001);
      expect(
        RoomMeasurementValidator.validate(
          timing: timing(),
          samples: silence,
          bins: bins,
          peaks: peaks,
          levels: RoomMeasurementValidator.calculateLevels(silence),
        ).join(' '),
        contains('too quiet'),
      );

      final clipped = List<double>.filled(441000, 1.0);
      expect(
        RoomMeasurementValidator.validate(
          timing: timing(),
          samples: clipped,
          bins: bins,
          peaks: peaks,
          levels: RoomMeasurementValidator.calculateLevels(clipped),
        ).join(' '),
        contains('too high'),
      );
    });

    test('valid PCM and finite ordered FFT output are accepted', () {
      final samples = List<double>.generate(
        441000,
        (index) => index.isEven ? 0.08 : -0.08,
      );
      final levels = RoomMeasurementValidator.calculateLevels(samples);
      expect(
        RoomMeasurementValidator.validate(
          timing: timing(),
          samples: samples,
          bins: bins,
          peaks: peaks,
          levels: levels,
        ),
        isEmpty,
      );
      expect(bins.every((bin) => bin.magnitude.isFinite), isTrue);
    });

    group('classifyQuality', () {
      const cleanLevels = CaptureLevelMetrics(
        rms: 0.08, // comfortably above minimumRms (0.002)
        peakAbsolute: 0.2,
        estimatedNoiseFloorDbfs: null,
        clippingRatio: 0,
        signalPresent: true,
        severelyClipped: false,
      );

      test('a clean, comfortably-above-threshold capture is valid', () {
        expect(
          RoomMeasurementValidator.classifyQuality(
            timing: timing(),
            levels: cleanLevels,
          ),
          CaptureQualityStatus.valid,
        );
      });

      test('a quiet signal just above the pass/fail floor is degraded', () {
        const quiet = CaptureLevelMetrics(
          rms: 0.0025, // above minimumRms (0.002) but within the 2.5x margin
          peakAbsolute: 0.05,
          estimatedNoiseFloorDbfs: null,
          clippingRatio: 0,
          signalPresent: true,
          severelyClipped: false,
        );
        expect(
          RoomMeasurementValidator.classifyQuality(
              timing: timing(), levels: quiet),
          CaptureQualityStatus.degraded,
        );
      });

      test('some (non-severe) clipping is degraded, not silently valid', () {
        const someClipping = CaptureLevelMetrics(
          rms: 0.08,
          peakAbsolute: 0.99,
          estimatedNoiseFloorDbfs: null,
          clippingRatio: 0.005, // > 0 but below severeClippingRatio (0.01)
          signalPresent: true,
          severelyClipped: false,
        );
        expect(
          RoomMeasurementValidator.classifyQuality(
              timing: timing(), levels: someClipping),
          CaptureQualityStatus.degraded,
        );
      });

      test(
          'a capture that ran noticeably short of its expected duration '
          'is degraded', () {
        final shortish = timing(
          samples: 400000,
          captured: const Duration(seconds: 9),
        );
        expect(
          RoomMeasurementValidator.classifyQuality(
              timing: shortish, levels: cleanLevels),
          CaptureQualityStatus.degraded,
        );
      });
    });
  });

  test('validated measurement stores real spectrum/peaks and derives result',
      () {
    final start = DateTime.utc(2026, 7, 17);
    final measurement = RoomMeasurement(
      id: 'measurement-1',
      roomType: 'Living Room',
      microphoneProfileId: 'Galaxy S20',
      hasMicrophoneCalibration: true,
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
        FrequencyBin(frequency: 90, magnitude: -18),
      ],
      peaks: const [ResonancePeak(frequency: 90, gain: -5, q: 4)],
      consistencyMetric: 1,
      levels: const CaptureLevelMetrics(
        rms: 0.08,
        peakAbsolute: 0.2,
        estimatedNoiseFloorDbfs: null,
        clippingRatio: 0,
        signalPresent: true,
        severelyClipped: false,
      ),
      quality: CaptureQualityStatus.valid,
      warnings: const [],
    );

    final decoded = RoomMeasurement.fromJson(measurement.toJson());
    expect(
        decoded.frequencyBins.singleWhere((b) => b.frequency == 90).magnitude,
        -18);
    expect(decoded.peaks.single.frequency, 90);

    final result = RoomScanResult.fromMeasurement(decoded);
    expect(result.measurementId, measurement.id);
    expect(result.validatedMeasurement, isTrue);
    expect(result.confidence, 'High');
    expect(result.cards, isNot(equals(kDefaultResultCards)));
    expect(result.cards.every((card) => card.evidenceKey != null), isTrue);
  });

  test(
      'confidence genuinely varies with real signal strength (rms), '
      'not stuck at a fixed value regardless of quality', () {
    RoomMeasurement withRms(double rms) {
      final start = DateTime.utc(2026, 7, 17);
      return RoomMeasurement(
        id: 'measurement-rms-$rms',
        roomType: 'Living Room',
        microphoneProfileId: 'Generic Phone Mic',
        // Deliberately uncalibrated in both cases: with calibration, the
        // other components alone already sum to exactly the "High"
        // threshold, leaving no room for rms headroom to matter. Without
        // it, whether rms headroom pushes the score over 0.85 becomes the
        // deciding factor — exactly what this test is checking.
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
          FrequencyBin(frequency: 90, magnitude: -18),
        ],
        peaks: const [ResonancePeak(frequency: 90, gain: -5, q: 4)],
        consistencyMetric: 1, // identical for both — must not affect the result
        levels: CaptureLevelMetrics(
          rms: rms,
          peakAbsolute: 0.2,
          estimatedNoiseFloorDbfs: null,
          clippingRatio: 0,
          signalPresent: rms >= RoomMeasurementValidator.minimumRms,
          severelyClipped: false,
        ),
        quality: CaptureQualityStatus.valid,
        warnings: const [],
      );
    }

    final strong = RoomScanResult.fromMeasurement(withRms(0.08));
    final barelyAbove = RoomScanResult.fromMeasurement(
        withRms(RoomMeasurementValidator.minimumRms));

    expect(strong.confidence, 'High');
    expect(barelyAbove.confidence, isNot('High'),
        reason: 'a signal barely above the usable floor must not score the '
            'same as a strong one — consistencyMetric alone used to mask '
            'this because it was always 1.0');
  });

  test('legacy RoomScanResult remains explicitly unvalidated', () {
    final legacy = RoomScanResult.fromJson({
      'roomType': 'Living Room',
      'micProfileName': 'Generic Phone Mic',
      'completedAt': DateTime.utc(2026).toIso8601String(),
      'confidence': 'Medium',
      'cards': kDefaultResultCards.map((card) => card.toJson()).toList(),
    });
    expect(legacy.schemaVersion, 0);
    expect(legacy.measurementId, isNull);
    expect(legacy.validatedMeasurement, isFalse);
  });

  test('real ROOM success path does not use default cards or fixed confidence',
      () {
    final source =
        File('lib/features/measure/measure_screen.dart').readAsStringSync();
    expect(source, isNot(contains('cards: kDefaultResultCards')));
    expect(source, isNot(contains("confidence: 'Medium'")));
    expect(source, contains('RoomScanResult.fromMeasurement(measurement)'));
  });

  test('ROOM lifecycle blocks duplicate capture and cancels unsafe sessions',
      () {
    final controller = File(
      'lib/features/measurement/measurement_controller.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/features/measure/measure_screen.dart',
    ).readAsStringSync();
    expect(controller, contains('if (_captureActive) return;'));
    expect(controller, contains('await _stopCapture();'));
    expect(screen, contains('didChangeAppLifecycleState'));
    expect(screen, contains('WidgetsBinding.instance.removeObserver(this)'));
    expect(screen, contains('next.connection != BleConnectionState.connected'));
    expect(screen, contains('cancelLoop()'));
  });
}
