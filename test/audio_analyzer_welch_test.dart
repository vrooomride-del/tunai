import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';

/// A sine at [freqHz] plus white noise, at the real capture sample rate.
Float64List _signal({
  required double seconds,
  required double freqHz,
  required double amplitude,
  required double noise,
  required int seed,
  double leadingSilenceSeconds = 0,
}) {
  final rng = math.Random(seed);
  final total = (AudioAnalyzer.sampleRate * seconds).round();
  final silent = (AudioAnalyzer.sampleRate * leadingSilenceSeconds).round();
  final out = Float64List(total);
  for (var i = 0; i < total; i++) {
    if (i < silent) {
      // Near-silence, as at the start of a real capture: recording begins
      // before playback does.
      out[i] = (rng.nextDouble() - 0.5) * 1e-4;
      continue;
    }
    final t = i / AudioAnalyzer.sampleRate;
    out[i] = amplitude * math.sin(2 * math.pi * freqHz * t) +
        (rng.nextDouble() - 0.5) * 2 * noise;
  }
  return out;
}

double _levelAt(List<FrequencyBin> bins, double freqHz) {
  var best = bins.first;
  for (final b in bins) {
    if ((b.frequency - freqHz).abs() < (best.frequency - freqHz).abs()) {
      best = b;
    }
  }
  return best.magnitude;
}

/// Spread of the noise floor away from the tone — the quantity that decides
/// whether random peaks get mistaken for room modes.
double _noiseFloorSpread(List<FrequencyBin> bins, double excludeHz) {
  final floor = bins
      .where((b) =>
          b.frequency > 200 &&
          b.frequency < 5000 &&
          (b.frequency - excludeHz).abs() > 50)
      .map((b) => b.magnitude)
      .toList();
  final mean = floor.reduce((a, b) => a + b) / floor.length;
  final variance =
      floor.map((m) => (m - mean) * (m - mean)).reduce((a, b) => a + b) /
          floor.length;
  return math.sqrt(variance);
}

void main() {
  group('AudioAnalyzer.performFFT — whole-recording averaging', () {
    test('a real 10s capture is averaged over many frames, not just the '
        'first 1.5 seconds', () {
      final samples =
          _signal(seconds: 10, freqHz: 1000, amplitude: 0.2, noise: 0.05, seed: 1);
      final bins = AudioAnalyzer.performFFT(samples);
      expect(bins, isNotEmpty);
      // The tone must still stand clearly above the floor.
      final tone = _levelAt(bins, 1000);
      final spread = _noiseFloorSpread(bins, 1000);
      expect(tone, greaterThan(-60));
      expect(spread, isNotNaN);
    });

    test('averaging measurably reduces the noise-floor spread — this is what '
        'stops random noise peaks reading as room resonances', () {
      // Same signal, one short enough to yield a single frame and one long
      // enough to average many. The only difference is how much of the
      // recording is used.
      final short =
          _signal(seconds: 1.4, freqHz: 1000, amplitude: 0.2, noise: 0.05, seed: 7);
      final long =
          _signal(seconds: 10, freqHz: 1000, amplitude: 0.2, noise: 0.05, seed: 7);

      final shortSpread =
          _noiseFloorSpread(AudioAnalyzer.performFFT(short), 1000);
      final longSpread =
          _noiseFloorSpread(AudioAnalyzer.performFFT(long), 1000);

      expect(longSpread, lessThan(shortSpread * 0.75),
          reason: 'averaging ~12 frames should cut the spread substantially; '
              'got short=$shortSpread long=$longSpread');
    });

    test('repeat captures of the same source agree far more closely than '
        'single-frame analysis did', () {
      // Different noise realisations, same underlying tone — exactly the
      // real-world case where the old code returned different "resonances"
      // every run.
      List<FrequencyBin> capture(int seed, double seconds) => AudioAnalyzer
          .performFFT(_signal(
              seconds: seconds,
              freqHz: 1000,
              amplitude: 0.2,
              noise: 0.05,
              seed: seed));

      double disagreement(double seconds) {
        final a = capture(11, seconds);
        final b = capture(22, seconds);
        var sum = 0.0;
        var n = 0;
        for (var i = 0; i < math.min(a.length, b.length); i++) {
          if (a[i].frequency < 200 || a[i].frequency > 5000) continue;
          sum += (a[i].magnitude - b[i].magnitude).abs();
          n++;
        }
        return sum / n;
      }

      expect(disagreement(10), lessThan(disagreement(1.4) * 0.75));
    });

    test('near-silent lead-in is excluded rather than dragging the spectrum '
        'down', () {
      // A capture that begins with 2 seconds of near-silence, as real ones do
      // (the recorder starts before playback).
      final withSilence = _signal(
          seconds: 10,
          freqHz: 1000,
          amplitude: 0.2,
          noise: 0.05,
          seed: 3,
          leadingSilenceSeconds: 2);
      final withoutSilence =
          _signal(seconds: 8, freqHz: 1000, amplitude: 0.2, noise: 0.05, seed: 3);

      final a = _levelAt(AudioAnalyzer.performFFT(withSilence), 1000);
      final b = _levelAt(AudioAnalyzer.performFFT(withoutSilence), 1000);
      expect((a - b).abs(), lessThan(2.0),
          reason: 'silent frames must not pull the measured level down');
    });

    test('a capture shorter than one frame still analyses, and an empty one '
        'returns nothing rather than fabricating a spectrum', () {
      final tiny = _signal(
          seconds: 0.3, freqHz: 1000, amplitude: 0.2, noise: 0.01, seed: 5);
      expect(AudioAnalyzer.performFFT(tiny), isNotEmpty);
      expect(AudioAnalyzer.performFFT(Float64List(0)), isEmpty);
    });

    test('bin frequencies stay within the analysed range and ascend', () {
      final bins = AudioAnalyzer.performFFT(
          _signal(seconds: 5, freqHz: 500, amplitude: 0.2, noise: 0.02, seed: 9));
      expect(bins.first.frequency, greaterThanOrEqualTo(20));
      expect(bins.last.frequency, lessThanOrEqualTo(20000));
      for (var i = 1; i < bins.length; i++) {
        expect(bins[i].frequency, greaterThan(bins[i - 1].frequency));
      }
    });
  });

  group('split-half agreement — how stable this spectrum estimate is', () {
    test('a capture with many usable frames agrees with itself far better '
        'than a single-frame one', () {
      // This is what the metric genuinely measures: how settled the spectrum
      // estimate is. It replaces a `consistencyMetric` that was the fraction
      // of finite bins — 1.0 by construction, measuring nothing.
      final long = AudioAnalyzer.analyzeCapture(_signal(
          seconds: 10, freqHz: 120, amplitude: 0.3, noise: 0.02, seed: 4));
      final short = AudioAnalyzer.analyzeCapture(_signal(
          seconds: 1.4, freqHz: 120, amplitude: 0.3, noise: 0.02, seed: 4));
      expect(short.agreement, 0,
          reason: 'a single frame has no second half to compare against, so '
              'nothing about it is corroborated');
      expect(long.agreement, greaterThan(0.5));
    });

    test('agreement improves as more of the recording is averaged', () {
      double agreementFor(double seconds) => AudioAnalyzer
          .analyzeCapture(_signal(
              seconds: seconds,
              freqHz: 120,
              amplitude: 0.3,
              noise: 0.05,
              seed: 12))
          .agreement;
      expect(agreementFor(20), greaterThan(agreementFor(3)));
    });

    test('an unusable capture reports zero agreement, never a confident '
        'empty result', () {
      expect(AudioAnalyzer.analyzeCapture(Float64List(0)).agreement, 0);
      expect(AudioAnalyzer.analyzeCapture(Float64List(0)).bins, isEmpty);
    });

    test('agreement is always a usable 0..1 score', () {
      for (final seconds in [0.5, 3.0, 10.0]) {
        final a = AudioAnalyzer.analyzeCapture(_signal(
                seconds: seconds,
                freqHz: 200,
                amplitude: 0.2,
                noise: 0.05,
                seed: 2))
            .agreement;
        expect(a, greaterThanOrEqualTo(0));
        expect(a, lessThanOrEqualTo(1));
      }
    });
  });
}
