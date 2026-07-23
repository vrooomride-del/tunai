import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/core/tune_result_summary.dart';

TuneCorrectionBand _band({
  required double frequencyHz,
  required double gainDb,
  TuneCorrectionSource source = TuneCorrectionSource.tonalBalance,
}) =>
    TuneCorrectionBand(
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: 1.0,
      evidenceReference: 'test',
      safetyValidated: true,
      source: source,
    );

TunePlan _plan(List<TuneCorrectionBand> bands) => TunePlan(
      id: 'plan-1',
      sourceMeasurementId: 'm-1',
      createdAt: DateTime.utc(2026),
      bands: bands,
      rejectedCandidates: const [],
      safetyBounds: const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: 1,
      warnings: const [],
    );

// Every generated line must stay in consumer language — this is a hard
// product rule, checked against both locales for every point a plan can emit.
const _forbiddenTerms = [
  'dB', 'Hz', 'PEQ', 'EQ', 'gain', 'frequency', 'Q ', 'FFT', 'DSP',
  'resonance', 'Hz', '데시벨', '주파수', '이퀄',
];

void _assertConsumerSafe(TuneResultSummary summary) {
  for (final point in summary.points) {
    for (final ko in [true, false]) {
      final text = point.label(ko: ko);
      for (final term in _forbiddenTerms) {
        expect(text.toLowerCase().contains(term.toLowerCase()), isFalse,
            reason: 'consumer copy must not contain "$term": "$text"');
      }
      expect(text.trim(), isNotEmpty);
    }
  }
}

void main() {
  group('TuneResultSummary', () {
    test('a null or empty plan produces no points and claims no change', () {
      expect(TuneResultSummary.of(null).hasAnyChange, isFalse);
      expect(TuneResultSummary.of(_plan(const [])).hasAnyChange, isFalse);
      expect(TuneResultSummary.of(null).points, isEmpty);
    });

    test('a real plan produces at least a headline plus the region it changed',
        () {
      final summary = TuneResultSummary.of(_plan([
        _band(frequencyHz: 80, gainDb: -4),
      ]));
      expect(summary.hasAnyChange, isTrue);
      expect(summary.points.length, greaterThanOrEqualTo(2));
      _assertConsumerSafe(summary);
    });

    test('a low-end CUT reads as tightening; a low-end LIFT reads as filling',
        () {
      final cut = TuneResultSummary.of(_plan([_band(frequencyHz: 80, gainDb: -4)]));
      final lift =
          TuneResultSummary.of(_plan([_band(frequencyHz: 80, gainDb: 3)]));
      expect(cut.points.any((p) => p.label(ko: false).contains('Tightened')),
          isTrue);
      expect(lift.points.any((p) => p.label(ko: false).contains('Filled')),
          isTrue);
    });

    test('two opposing small moves in the same region cancel rather than both '
        'being announced', () {
      // Net-zero in the low region: must not claim both "tightened" AND
      // "filled". The signed sum is what a listener would perceive.
      final summary = TuneResultSummary.of(_plan([
        _band(frequencyHz: 60, gainDb: -3),
        _band(frequencyHz: 120, gainDb: 3),
      ]));
      final lowLines = summary.points
          .where((p) =>
              p.label(ko: false).contains('low end') ||
              p.label(ko: false).contains('Tightened') ||
              p.label(ko: false).contains('Filled'))
          .length;
      expect(lowLines, lessThanOrEqualTo(1));
    });

    test('the headline names both room-response and tone when both correction '
        'sources are present', () {
      final summary = TuneResultSummary.of(_plan([
        _band(
            frequencyHz: 80,
            gainDb: -4,
            source: TuneCorrectionSource.roomMode),
        _band(
            frequencyHz: 3000,
            gainDb: -3,
            source: TuneCorrectionSource.tonalBalance),
      ]));
      final headline = summary.points.first.label(ko: false);
      expect(headline.toLowerCase(), contains('room'));
      expect(headline.toLowerCase(), contains('tone'));
      _assertConsumerSafe(summary);
    });

    test('corrections across the full range each get their own line', () {
      final summary = TuneResultSummary.of(_plan([
        _band(frequencyHz: 80, gainDb: -4),
        _band(frequencyHz: 700, gainDb: -3),
        _band(frequencyHz: 4000, gainDb: -3),
      ]));
      final joined =
          summary.points.map((p) => p.label(ko: false)).join(' | ');
      expect(joined.toLowerCase(), contains('low'));
      expect(joined.toLowerCase(), anyOf(contains('mid'), contains('boxy')));
      expect(joined.toLowerCase(), anyOf(contains('treble'), contains('top')));
      _assertConsumerSafe(summary);
    });

    test('all generated copy stays consumer-safe for every plan shape', () {
      for (final bands in [
        [_band(frequencyHz: 50, gainDb: -6)],
        [_band(frequencyHz: 1000, gainDb: 3)],
        [_band(frequencyHz: 8000, gainDb: -2)],
        [
          _band(frequencyHz: 60, gainDb: -3, source: TuneCorrectionSource.roomMode),
          _band(frequencyHz: 500, gainDb: 2),
          _band(frequencyHz: 5000, gainDb: -3),
        ],
      ]) {
        _assertConsumerSafe(TuneResultSummary.of(_plan(bands)));
      }
    });
  });
}
