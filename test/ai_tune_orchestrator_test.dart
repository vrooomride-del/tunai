import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/ai_tune_orchestrator.dart';
import 'package:tunai/core/ai_tuning_service.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/consumer_sound_profile.dart'
    show ConsumerDspDeploymentRecordResult;
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/sound_score_calculator.dart';
import 'package:tunai/core/tune_outcome_history.dart';
import 'package:tunai/core/tune_plan.dart';

RoomMeasurement _measurement() {
  final start = DateTime.utc(2026, 7, 17);
  return RoomMeasurement(
    id: 'measurement-ai-orchestrator',
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

TunePlan _rulePlan(RoomMeasurement measurement) =>
    TunePlanner(now: () => DateTime.utc(2026, 7, 17)).generate(measurement);

void main() {
  group('AiTuneOrchestrator', () {
    test('AI success: validated bands replace the rule-based plan', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            const AiTuningResult(
          bands: [
            {
              'frequency': 100.0,
              'gainDb': -4.0,
              'q': 2.0,
              'enabled': true,
              'reason': '저역을 정리했습니다.',
            },
          ],
          explanation: '저역 울림을 줄였습니다.',
          soundScore: 82,
        ),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isTrue);
      expect(result.plan.bands.single.frequencyHz, 100.0);
      expect(result.plan.bands.single.gainDb, -4.0);
      // Metadata shell (id, measurement linkage, safety bounds) comes from
      // rulePlan — only the bands themselves are AI-sourced.
      expect(result.plan.id, rulePlan.id);
      expect(result.plan.sourceMeasurementId, rulePlan.sourceMeasurementId);
    });

    test('network/exception failure falls back to the rule-based plan',
        () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            throw Exception('network unreachable'),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
      expect(result.aiFailureReason, isNotNull);
    });

    test('AI isError result falls back to the rule-based plan', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            AiTuningResult.error('AI 오류: unavailable'),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
    });

    test('empty AI bands falls back to the rule-based plan', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            const AiTuningResult(bands: [], explanation: 'no bands'),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
    });

    test('excessive gain is rejected by the Safety Validator, falls back',
        () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            const AiTuningResult(
          bands: [
            // -24dB far exceeds TuneSafetyBounds.maximumCutDb (default 6dB).
            {'frequency': 100.0, 'gainDb': -24.0, 'q': 2.0, 'enabled': true},
          ],
          explanation: 'excessive cut',
        ),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
    });

    test(
        'out-of-bounds frequency is rejected by the Safety Validator, '
        'falls back', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            const AiTuningResult(
          bands: [
            // 15kHz is far outside TuneSafetyBounds. (8000Hz used to serve
            // here, but that is now the legitimate ceiling of the
            // full-range profile — see TuneSafetyBounds.consumerFullRange.)
            {'frequency': 15000.0, 'gainDb': -3.0, 'q': 2.0, 'enabled': true},
          ],
          explanation: 'out of range frequency',
        ),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
    });

    test('unparseable/unsupported-parameter bands are dropped, falls back',
        () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            const AiTuningResult(
          bands: [
            // Missing 'q' — cannot be parsed into a TuneCorrectionBand.
            {'frequency': 100.0, 'gainDb': -3.0, 'enabled': true},
            // Disabled — excluded even though otherwise well-formed.
            {
              'frequency': 200.0,
              'gainDb': -3.0,
              'q': 2.0,
              'enabled': false,
            },
          ],
          explanation: 'malformed response',
        ),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
    });

    test('timeout falls back to the rule-based plan', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        timeout: const Duration(milliseconds: 30),
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async {
          await Future.delayed(const Duration(milliseconds: 200));
          return const AiTuningResult(
            bands: [
              {'frequency': 100.0, 'gainDb': -3.0, 'q': 2.0, 'enabled': true},
            ],
            explanation: 'too slow',
          );
        },
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isFalse);
      expect(result.plan, same(rulePlan));
      expect(result.aiFailureReason, isNotNull);
    });

    test(
        'AI recommendation never bypasses TuneSafetyValidator: only the '
        'approved band survives when the AI mixes safe and unsafe bands',
        () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async =>
            const AiTuningResult(
          bands: [
            {'frequency': 100.0, 'gainDb': -3.0, 'q': 2.0, 'enabled': true},
            // Unsafe: exceeds maximumCutDb.
            {'frequency': 300.0, 'gainDb': -20.0, 'q': 2.0, 'enabled': true},
          ],
          explanation: 'mixed safety',
        ),
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.usedAiRecommendation, isTrue);
      expect(result.plan.bands.length, 1);
      expect(result.plan.bands.single.frequencyHz, 100.0);
    });

    test(
        'AI Acoustic Reasoning: real room type, measurement quality, and '
        'current Sound Score are passed through to the AI call', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      String? capturedUserRequest;
      String? capturedLocation;
      SoundScoreResult? capturedScore;
      final orchestrator = AiTuneOrchestrator(
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async {
          capturedUserRequest = userRequest;
          capturedLocation = location;
          capturedScore = soundScore;
          return const AiTuningResult(bands: [], explanation: 'no bands');
        },
      );
      final score = SoundScoreCalculator.compute(measurement.frequencyBins);

      await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.warm,
        currentScore: score,
      );

      // Real room type — the same value TunePlanner/ConsumerSoundProfile
      // already carry, not a fabricated label.
      expect(capturedLocation, measurement.roomType);
      // Real measurement quality + the chosen preset preference's own
      // description, not raw free text.
      expect(capturedUserRequest, contains('측정 신뢰도 높음'));
      expect(capturedUserRequest,
          contains(SoundPreference.warm.description(ko: true)));
      // The real, already-computed Sound Score is threaded through
      // unmodified — never recomputed or fabricated inside the orchestrator.
      expect(capturedScore, same(score));
    });

    test(
        'Closed Loop: real recent Apply outcomes are summarized into the '
        'AI request', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      String? capturedUserRequest;
      final orchestrator = AiTuneOrchestrator(
        loadRecentOutcomes: () async => [
          TuneOutcomeRecord(
            tunePlanId: 'other-plan',
            measurementId: 'other-measurement',
            preference: SoundPreference.vocal,
            usedAiRecommendation: true,
            result: ConsumerDspDeploymentRecordResult.applied,
            soundScoreBefore: 60,
            soundScoreAfter: 80,
            recordedAt: DateTime.utc(2026, 7, 20),
          ),
          TuneOutcomeRecord(
            tunePlanId: 'other-plan-2',
            preference: SoundPreference.warm,
            usedAiRecommendation: false,
            result: ConsumerDspDeploymentRecordResult.failed,
            recordedAt: DateTime.utc(2026, 7, 19),
          ),
        ],
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async {
          capturedUserRequest = userRequest;
          return const AiTuningResult(bands: [], explanation: 'no bands');
        },
      );

      await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      // Real counts from the real (injected) history — one success, one
      // failure — and the most recent entry's own real preference/result.
      expect(capturedUserRequest, contains('성공 1회'));
      expect(capturedUserRequest, contains('실패 1회'));
      expect(capturedUserRequest,
          contains(SoundPreference.vocal.description(ko: true)));
      expect(capturedUserRequest, contains('직전 결과 개선됨'));
    });

    test(
        'Closed Loop: an outcome-history failure never blocks Tune '
        'generation — falls back to no history context', () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      String? capturedUserRequest;
      final orchestrator = AiTuneOrchestrator(
        loadRecentOutcomes: () async => throw Exception('history unavailable'),
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async {
          capturedUserRequest = userRequest;
          return const AiTuningResult(bands: [], explanation: 'no bands');
        },
      );

      final result = await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(result.plan, same(rulePlan));
      expect(capturedUserRequest, isNotNull);
      expect(capturedUserRequest, isNot(contains('최근 조정 이력')));
    });

    test('no history yet: the AI request omits any outcome summary',
        () async {
      final measurement = _measurement();
      final rulePlan = _rulePlan(measurement);
      String? capturedUserRequest;
      final orchestrator = AiTuneOrchestrator(
        loadRecentOutcomes: () async => const [],
        suggest: ({
          required peaks,
          required userRequest,
          speakerProfile,
          location,
          spectrum,
          soundScore,
        }) async {
          capturedUserRequest = userRequest;
          return const AiTuningResult(bands: [], explanation: 'no bands');
        },
      );

      await orchestrator.orchestrate(
        measurement: measurement,
        rulePlan: rulePlan,
        preference: SoundPreference.balanced,
      );

      expect(capturedUserRequest, isNot(contains('최근 조정 이력')));
    });

    group('AiDecisionMetadata', () {
      test('AI success with every proposed band validated → high confidence',
          () async {
        final measurement = _measurement(); // CaptureQualityStatus.valid
        final rulePlan = _rulePlan(measurement);
        final orchestrator = AiTuneOrchestrator(
          suggest: ({
            required peaks,
            required userRequest,
            speakerProfile,
            location,
            spectrum,
            soundScore,
          }) async =>
              const AiTuningResult(
            bands: [
              {'frequency': 100.0, 'gainDb': -3.0, 'q': 2.0, 'enabled': true},
            ],
            explanation: 'ok',
          ),
        );

        final result = await orchestrator.orchestrate(
          measurement: measurement,
          rulePlan: rulePlan,
          preference: SoundPreference.balanced,
        );

        expect(result.metadata.usedAiRecommendation, isTrue);
        expect(result.metadata.confidence, AiDecisionConfidence.high);
        expect(result.metadata.proposedBandCount, 1);
        expect(result.metadata.validatedBandCount, 1);
        expect(result.metadata.fallbackReason, isNull);
      });

      test(
          'AI success with only some proposed bands surviving validation → '
          'medium confidence', () async {
        final measurement = _measurement();
        final rulePlan = _rulePlan(measurement);
        final orchestrator = AiTuneOrchestrator(
          suggest: ({
            required peaks,
            required userRequest,
            speakerProfile,
            location,
            spectrum,
            soundScore,
          }) async =>
              const AiTuningResult(
            bands: [
              {'frequency': 100.0, 'gainDb': -3.0, 'q': 2.0, 'enabled': true},
              // Unsafe: exceeds maximumCutDb, gets rejected by the validator.
              {'frequency': 300.0, 'gainDb': -20.0, 'q': 2.0, 'enabled': true},
            ],
            explanation: 'mixed',
          ),
        );

        final result = await orchestrator.orchestrate(
          measurement: measurement,
          rulePlan: rulePlan,
          preference: SoundPreference.balanced,
        );

        expect(result.metadata.usedAiRecommendation, isTrue);
        expect(result.metadata.proposedBandCount, 2);
        expect(result.metadata.validatedBandCount, 1);
        expect(result.metadata.confidence, AiDecisionConfidence.medium);
      });

      test('rule-based fallback with valid measurement → medium confidence',
          () async {
        final measurement = _measurement(); // valid
        final rulePlan = _rulePlan(measurement);
        final orchestrator = AiTuneOrchestrator(
          suggest: ({
            required peaks,
            required userRequest,
            speakerProfile,
            location,
            spectrum,
            soundScore,
          }) async =>
              const AiTuningResult(bands: [], explanation: 'no bands'),
        );

        final result = await orchestrator.orchestrate(
          measurement: measurement,
          rulePlan: rulePlan,
          preference: SoundPreference.balanced,
        );

        expect(result.metadata.usedAiRecommendation, isFalse);
        expect(result.metadata.confidence, AiDecisionConfidence.medium);
        expect(result.metadata.fallbackReason, isNotNull);
      });

      test('never fabricates confidence: it is always derived from real '
          'validation counts and real measurement quality only', () async {
        final measurement = _measurement();
        final rulePlan = _rulePlan(measurement);
        final orchestrator = AiTuneOrchestrator(
          suggest: ({
            required peaks,
            required userRequest,
            speakerProfile,
            location,
            spectrum,
            soundScore,
          }) async =>
              throw Exception('network unreachable'),
        );

        final result = await orchestrator.orchestrate(
          measurement: measurement,
          rulePlan: rulePlan,
          preference: SoundPreference.balanced,
        );

        expect(result.metadata.proposedBandCount, 0);
        expect(result.metadata.validatedBandCount, 0);
        expect(result.metadata.fallbackReason, contains('network unreachable'));
      });
    });

    group('AiProvider boundary', () {
      test('GeminiAiProvider implements AiProvider', () {
        const provider = GeminiAiProvider();
        expect(provider, isA<AiProvider>());
      });
    });
  });
}
