import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/acoustic_analysis.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/tune_plan.dart';

TuneCorrectionBand _band(double f, double g,
        [TuneCorrectionSource s = TuneCorrectionSource.tonalBalance]) =>
    TuneCorrectionBand(
      frequencyHz: f,
      gainDb: g,
      q: 1,
      evidenceReference: 't',
      safetyValidated: true,
      source: s,
    );

TunePlan _plan(List<TuneCorrectionBand> bands, {double consistency = 1}) =>
    TunePlan(
      id: 'p',
      sourceMeasurementId: 'm',
      createdAt: DateTime.utc(2026),
      bands: bands,
      rejectedCandidates: const [],
      safetyBounds: const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: consistency,
      warnings: const [],
    );

void main() {
  group('AcousticAnalysis.of — defensive parsing', () {
    test('null / empty / all-blank json yields null (card hidden)', () {
      expect(AcousticAnalysis.of(null), isNull);
      expect(AcousticAnalysis.of({}), isNull);
      expect(
          AcousticAnalysis.of(
              {'summary': '   ', 'improvements': [], 'placementAdvice': ''}),
          isNull);
    });

    test('keeps only real fields, drops blanks and wrong types', () {
      final a = AcousticAnalysis.of({
        'summary': '공간의 저음을 정리했습니다.',
        'changes': ['저음이 단단해졌어요', '', 42, '음색이 균형잡혔어요'],
        'placementAdvice': '   ',
        'listeningAdvice': '균형 잡힌 소리를 경험할 수 있습니다',
        'confidenceExplanation': 123,
      })!;
      expect(a.summary, '공간의 저음을 정리했습니다.');
      expect(a.changes, ['저음이 단단해졌어요', '음색이 균형잡혔어요']);
      expect(a.listeningAdvice, '균형 잡힌 소리를 경험할 수 있습니다');
      expect(a.placementAdvice, isNull);
      expect(a.confidenceExplanation, isNull);
      expect(a.hasContent, isTrue);
    });

    test('a single non-empty field is enough to show the card', () {
      final a = AcousticAnalysis.of({'placementAdvice': '스피커를 벽에서 조금 띄워보세요.'})!;
      expect(a.hasContent, isTrue);
      expect(a.summary, isNull);
    });

    test('legacy "improvements" key is still accepted as an alias for changes',
        () {
      final a = AcousticAnalysis.of({
        'summary': '조정했습니다.',
        'improvements': ['저음 정리'],
      })!;
      expect(a.changes, ['저음 정리']);
    });
  });

  group('AcousticAnalysisDigest.of — safe, real-data-only input', () {
    test('no plan / empty plan yields null — AI never narrates nothing', () {
      expect(
          AcousticAnalysisDigest.of(plan: null, captureAgreement: 1), isNull);
      expect(
          AcousticAnalysisDigest.of(plan: _plan(const []), captureAgreement: 1),
          isNull);
    });

    test('buckets bands into region + net direction', () {
      final digest = AcousticAnalysisDigest.of(
        plan: _plan([
          _band(80, -4), // low reduced
          _band(3000, 3), // high lifted
        ]),
        captureAgreement: 0.9,
      )!;
      final low =
          digest.corrections.firstWhere((c) => c.region == ToneRegion.low);
      final high =
          digest.corrections.firstWhere((c) => c.region == ToneRegion.high);
      expect(low.direction, ToneDirection.reduced);
      expect(high.direction, ToneDirection.lifted);
    });

    test('opposing moves in one region net to a single direction', () {
      final digest = AcousticAnalysisDigest.of(
        plan: _plan([_band(60, -3), _band(120, 5)]),
        captureAgreement: 0.9,
      )!;
      final lows =
          digest.corrections.where((c) => c.region == ToneRegion.low).toList();
      expect(lows, hasLength(1));
      expect(lows.single.direction, ToneDirection.lifted); // net +2
    });

    test('confidence label comes from real capture agreement', () {
      TunePlan p() => _plan([_band(80, -4)]);
      expect(
          AcousticAnalysisDigest.of(plan: p(), captureAgreement: 0.9)!
              .confidenceLabel,
          'stable');
      expect(
          AcousticAnalysisDigest.of(plan: p(), captureAgreement: 0.6)!
              .confidenceLabel,
          'moderate');
      expect(
          AcousticAnalysisDigest.of(plan: p(), captureAgreement: 0.2)!
              .confidenceLabel,
          'low');
    });

    test('the wire payload carries only coarse descriptors — no dB/Hz/Q', () {
      final json = AcousticAnalysisDigest.of(
        plan: _plan([
          _band(80, -4, TuneCorrectionSource.roomMode),
          _band(700, -3),
        ]),
        captureAgreement: 0.9,
        placement: 'near_wall',
      )!
          .toJson();
      final serialized = json.toString();
      for (final term in ['80', '700', '-4', '-3', 'Hz', 'dB', 'gain', 'q:']) {
        expect(serialized.contains(term), isFalse,
            reason: 'digest payload must not leak "$term": $serialized');
      }
      expect(json['placement'], 'near_wall');
      expect(json['usedRoomModeCorrection'], isTrue);
      expect(json['usedTonalBalanceCorrection'], isTrue);
      expect(json['confidence'], 'stable');
    });

    test('placement is omitted from the payload when not chosen', () {
      final json = AcousticAnalysisDigest.of(
        plan: _plan([_band(80, -4)]),
        captureAgreement: 0.9,
      )!
          .toJson();
      expect(json.containsKey('placement'), isFalse);
    });
  });
}
