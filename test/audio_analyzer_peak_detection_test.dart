import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';

/// Builds a flat-floor deviation spectrum with a single triangular bump
/// inserted at [bumpFrequencyHz], mirroring the shape `detectPeaks` actually
/// receives (measured − pink reference; see measurement_controller.dart).
///
/// [halfWidthHz] controls how quickly the bump falls off — for a linear
/// (triangular) ramp of height [bumpDb] and half-width [halfWidthHz], the
/// -3dB-down half-width is exactly `halfWidthHz * 3 / bumpDb`, which makes
/// the expected Q analytically predictable for tests:
/// `Q = bumpFrequencyHz / (2 * halfWidthHz * 3 / bumpDb)`.
List<FrequencyBin> _spectrumWithBump({
  required double bumpFrequencyHz,
  double bumpDb = 6,
  double halfWidthHz = 8,
  double floorDb = 0,
  double maxFrequencyHz = 600,
}) {
  const binHz = 0.67; // ~65536-point FFT @ 44.1kHz resolution
  final bins = <FrequencyBin>[];
  for (var f = 20.0; f <= maxFrequencyHz; f += binHz) {
    final distance = (f - bumpFrequencyHz).abs();
    final bump =
        bumpDb * (distance < halfWidthHz ? (1 - distance / halfWidthHz) : 0);
    bins.add(FrequencyBin(frequency: f, magnitude: floorDb + bump));
  }
  return bins;
}

void main() {
  group('AudioAnalyzer.detectPeaks room-mode search band', () {
    test('finds a genuine low-frequency room mode (e.g. 120Hz)', () {
      final spectrum = _spectrumWithBump(bumpFrequencyHz: 120);
      final peaks = AudioAnalyzer.detectPeaks(spectrum);
      expect(peaks, isNotEmpty);
      expect(peaks.any((p) => (p.frequency - 120).abs() < 5), isTrue);
    });

    test(
        'does NOT surface a bump at 400Hz — above the room-mode search ceiling',
        () {
      final spectrum = _spectrumWithBump(bumpFrequencyHz: 400);
      final peaks = AudioAnalyzer.detectPeaks(spectrum);
      expect(peaks, isEmpty);
    });

    test('search ceiling is exactly 300Hz', () {
      expect(AudioAnalyzer.roomModeSearchCeilingHz, 300);
    });

    test(
        'a bump above the ceiling (310Hz) is excluded, one comfortably below (250Hz) is found',
        () {
      final above = _spectrumWithBump(bumpFrequencyHz: 310);
      // 250Hz, not right at the edge: the local-max scan needs a full
      // ±20Hz window inside the truncated band, so a bump too close to the
      // 300Hz edge is structurally unscannable regardless of the fix here.
      final below = _spectrumWithBump(bumpFrequencyHz: 250);

      expect(AudioAnalyzer.detectPeaks(above), isEmpty);
      expect(AudioAnalyzer.detectPeaks(below), isNotEmpty);
    });

    test('flat spectrum (no room mode) yields no peaks', () {
      final flat = _spectrumWithBump(bumpFrequencyHz: 120, bumpDb: 0);
      expect(AudioAnalyzer.detectPeaks(flat), isEmpty);
    });
  });

  group('AudioAnalyzer.detectPeaks adaptive Q (bandwidth-derived)', () {
    test('a narrow resonance yields a higher Q than a wide, gentle boom', () {
      // Narrow: halfWidthHz=8, bumpDb=6 → -3dB half-width = 8*3/6 = 4Hz →
      // bandwidth 8Hz → Q ≈ 120/8 = 15.
      final narrow = AudioAnalyzer.detectPeaks(
        _spectrumWithBump(bumpFrequencyHz: 120, bumpDb: 6, halfWidthHz: 8),
      );
      // Wide: halfWidthHz=24, bumpDb=6 → -3dB half-width = 24*3/6 = 12Hz →
      // bandwidth 24Hz → Q ≈ 120/24 = 5.
      final wide = AudioAnalyzer.detectPeaks(
        _spectrumWithBump(bumpFrequencyHz: 120, bumpDb: 6, halfWidthHz: 24),
      );

      expect(narrow, isNotEmpty);
      expect(wide, isNotEmpty);
      expect(narrow.single.q, closeTo(15, 1.5));
      expect(wide.single.q, closeTo(5, 1.5));
      // The core requirement: narrow room resonance → materially higher Q
      // than a broad bass boom, not the old fixed 4.0 for both.
      expect(narrow.single.q, greaterThan(wide.single.q * 2));
    });

    test('Q is no longer hardcoded to 4.0 for every peak', () {
      final peaks = AudioAnalyzer.detectPeaks(
        _spectrumWithBump(bumpFrequencyHz: 150, bumpDb: 8, halfWidthHz: 6),
      );
      expect(peaks, isNotEmpty);
      expect(peaks.single.q, isNot(closeTo(4.0, 0.01)));
    });

    test(
        'falls back to the default Q when the bump never crosses -3dB within the search window',
        () {
      // halfWidthHz=60, bumpDb=6 → -3dB half-width = 60*3/6 = 30Hz, which
      // exceeds the ±20Hz (halfWin=30 bin) local-max/Q search window, so the
      // -3dB point is never found — must degrade to the safe fallback, not
      // an unstable/undefined value.
      final peaks = AudioAnalyzer.detectPeaks(
        _spectrumWithBump(bumpFrequencyHz: 150, bumpDb: 6, halfWidthHz: 60),
      );
      expect(peaks, isNotEmpty);
      expect(peaks.single.q, AudioAnalyzer.defaultPeakQ);
    });

    test('estimated Q is always finite and positive', () {
      for (final halfWidth in [4.0, 8.0, 16.0, 30.0, 60.0, 100.0]) {
        final peaks = AudioAnalyzer.detectPeaks(
          _spectrumWithBump(
              bumpFrequencyHz: 140, bumpDb: 5, halfWidthHz: halfWidth),
        );
        for (final p in peaks) {
          expect(p.q.isFinite, isTrue);
          expect(p.q, greaterThan(0));
        }
      }
    });

    test(
        'a very sharp resonance is clamped to maxEstimatedQ (16), not left '
        'unbounded — regression test: an unclamped Q here used to fail '
        'RoomMeasurementValidator.validate() (q > 16) even though capture '
        'and peak detection both succeeded, silently bouncing Room Scan '
        'back to its own screen', () {
      // halfWidthHz=1, bumpDb=6 → -3dB half-width = 1*3/6 = 0.5Hz →
      // bandwidth ~1Hz → raw Q ≈ 120/1 ≈ 120, far above the validator's
      // accepted [0.3, 16] range.
      final peaks = AudioAnalyzer.detectPeaks(
        _spectrumWithBump(bumpFrequencyHz: 120, bumpDb: 6, halfWidthHz: 1),
      );
      expect(peaks, isNotEmpty);
      expect(peaks.single.q, AudioAnalyzer.maxEstimatedQ);
    });

    test('estimated Q never falls outside the validator-accepted range', () {
      for (final halfWidth in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 30.0, 60.0]) {
        final peaks = AudioAnalyzer.detectPeaks(
          _spectrumWithBump(
              bumpFrequencyHz: 130, bumpDb: 6, halfWidthHz: halfWidth),
        );
        for (final p in peaks) {
          expect(p.q, greaterThanOrEqualTo(AudioAnalyzer.minEstimatedQ));
          expect(p.q, lessThanOrEqualTo(AudioAnalyzer.maxEstimatedQ));
        }
      }
    });
  });
}
