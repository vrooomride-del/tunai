import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/broadband_tone_analyzer.dart';

/// Builds a log-spaced spectrum from a shape function, at roughly the bin
/// density Room Scan actually produces.
List<FrequencyBin> _spectrum(double Function(double freqHz) magnitudeAt) {
  final bins = <FrequencyBin>[];
  for (var f = 20.0; f <= 10000; f *= 1.002) {
    bins.add(FrequencyBin(frequency: f, magnitude: magnitudeAt(f)));
  }
  return bins;
}

/// A gaussian bump in log-frequency — stands in for a broad tonal imbalance.
double _bump(double f, {required double centerHz, required double gainDb,
    double widthOctaves = 0.5}) {
  final octaves = math.log(f / centerHz) / math.ln2;
  return gainDb * math.exp(-(octaves * octaves) / (2 * widthOctaves * widthOctaves));
}

void main() {
  group('BroadbandToneAnalyzer', () {
    test('a perfectly flat response needs no correction', () {
      final corrections = BroadbandToneAnalyzer.analyze(_spectrum((_) => -70));
      expect(corrections, isEmpty);
    });

    test('a broad tilt alone needs no correction — that is microphone and '
        'speaker voicing, not the room', () {
      // A steady slope has no LOCAL deviation from its own trend, which is
      // exactly the point of the self-referenced target: an uncalibrated
      // phone mic's fixed response must not be "corrected" as if it were the
      // room.
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) => -70 - 3 * math.log(f / 1000) / math.ln2),
      );
      expect(corrections, isEmpty);
    });

    test('a broad excess is cut at roughly the right frequency', () {
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) => -70 + _bump(f, centerHz: 700, gainDb: 8)),
      );
      expect(corrections, isNotEmpty);
      final mid = corrections.firstWhere((c) => c.frequencyHz > 300);
      expect(mid.gainDb, lessThan(0), reason: 'too much energy → cut');
      expect(mid.frequencyHz, greaterThan(450));
      expect(mid.frequencyHz, lessThan(1100));
    });

    test('a broad dip is boosted — the whole point of allowing gain, since a '
        'cut-only plan can never lift a region that measured low', () {
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) => -70 + _bump(f, centerHz: 700, gainDb: -8)),
      );
      expect(corrections, isNotEmpty);
      final mid = corrections.firstWhere((c) => c.frequencyHz > 300);
      expect(mid.gainDb, greaterThan(0));
      expect(mid.gainDb,
          lessThanOrEqualTo(BroadbandToneAnalyzer.maximumBoostDb));
    });

    test('gains stay inside the asymmetric limits the deployment protocol '
        'itself accepts (-6..+3dB)', () {
      for (final depth in [30.0, -30.0]) {
        final corrections = BroadbandToneAnalyzer.analyze(
          _spectrum((f) => -70 + _bump(f, centerHz: 700, gainDb: depth)),
        );
        for (final c in corrections) {
          expect(c.gainDb, greaterThanOrEqualTo(-BroadbandToneAnalyzer.maximumCutDb));
          expect(c.gainDb, lessThanOrEqualTo(BroadbandToneAnalyzer.maximumBoostDb));
        }
      }
    });

    test('never emits more corrections than the hardware can deploy, and '
        'never two in the same region', () {
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) =>
            -70 +
            _bump(f, centerHz: 100, gainDb: 9) +
            _bump(f, centerHz: 700, gainDb: -9) +
            _bump(f, centerHz: 3000, gainDb: 9)),
      );
      expect(corrections.length,
          lessThanOrEqualTo(BroadbandToneAnalyzer.regions.length));
      final regionsHit = corrections
          .map((c) => BroadbandToneAnalyzer.regions
              .indexWhere((r) => c.frequencyHz >= r.lowHz && c.frequencyHz < r.highHz))
          .toList();
      expect(regionsHit.toSet().length, regionsHit.length,
          reason: 'one correction per region at most');
    });

    test('corrects across the FULL range, not only room modes below 300Hz', () {
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) => -70 + _bump(f, centerHz: 3000, gainDb: 8)),
      );
      expect(corrections, isNotEmpty);
      expect(corrections.any((c) => c.frequencyHz > 1500), isTrue,
          reason: 'AudioAnalyzer.detectPeaks stops at 300Hz; this must not');
    });

    test('a small wobble under the noise floor is left alone', () {
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) => -70 + _bump(f, centerHz: 700, gainDb: 1.5)),
      );
      expect(corrections, isEmpty,
          reason: 'below minimumDeviationDb — normal capture variation must '
              'never manufacture a correction');
    });

    test('degenerate input returns nothing rather than a fabricated result',
        () {
      expect(BroadbandToneAnalyzer.analyze(const []), isEmpty);
      expect(
        BroadbandToneAnalyzer.analyze(
            const [FrequencyBin(frequency: 100, magnitude: -70)]),
        isEmpty,
      );
    });

    test('emitted Q is broad and inside the safety bounds', () {
      final corrections = BroadbandToneAnalyzer.analyze(
        _spectrum((f) => -70 + _bump(f, centerHz: 700, gainDb: 8)),
      );
      for (final c in corrections) {
        expect(c.q, BroadbandToneAnalyzer.correctionQ);
        expect(c.q, greaterThanOrEqualTo(0.7));
        expect(c.q, lessThanOrEqualTo(8));
      }
    });
  });
}
