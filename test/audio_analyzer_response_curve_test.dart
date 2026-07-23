// Regression guard for the Consumer Room Balance graph's "monotonic
// descending line" bug: the CCV-corrected spectrum (`applyCCV` output, what
// `scmsBins` holds) is deliberately built to collapse toward the pink
// reference's own smooth, monotonically-decreasing shape once de-meaned —
// that's what makes room-mode peaks detectable as deviations elsewhere, but
// it also makes it meaningless to plot directly as "the room's response".
// `measured - srefDb` (what responseBins/deviationBins holds) keeps real
// peaks visible instead. This test proves the property in isolation so the
// same field mix-up can't silently regress the chart again.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/audio_analyzer.dart';

bool _isMonotonicNonIncreasing(List<FrequencyBin> bins, {double tolerance = 0.05}) {
  for (var i = 1; i < bins.length; i++) {
    if (bins[i].magnitude > bins[i - 1].magnitude + tolerance) return false;
  }
  return true;
}

void main() {
  test('a measured spectrum with a real room-mode peak has a non-monotonic '
      'deviation-from-reference curve (the correct "before" data)', () {
    // Synthetic "measured" spectrum: pink-noise-shaped baseline (srefDb)
    // plus one real +6dB bump at 120Hz, exactly the shape a genuine room
    // mode would produce.
    final measured = [
      for (double f = 20; f <= 500; f += 10)
        FrequencyBin(
          frequency: f,
          magnitude: AudioAnalyzer.srefDb(f) + (f >= 100 && f <= 140 ? 6 : 0),
        ),
    ];

    final deviation = measured
        .map((b) => FrequencyBin(
              frequency: b.frequency,
              magnitude: b.magnitude - AudioAnalyzer.srefDb(b.frequency),
            ))
        .toList();

    // The peak survives as a real local maximum in the deviation curve...
    expect(_isMonotonicNonIncreasing(deviation), isFalse,
        reason: 'a real +6dB room mode must show up as a bump, not be '
            'absorbed into a smooth downward line');
  });

  test('CCV-corrected spectrum (scmsBins) collapses toward the smooth pink '
      'reference shape even when the room had a real peak — confirming it '
      'is the wrong curve to visualize as "the room\'s response"', () {
    final measured = [
      for (double f = 20; f <= 500; f += 10)
        FrequencyBin(
          frequency: f,
          magnitude: AudioAnalyzer.srefDb(f) + (f >= 100 && f <= 140 ? 6 : 0),
        ),
    ];

    final ccv = AudioAnalyzer.calculateCCV(measured);
    final scmsBins = AudioAnalyzer.applyCCV(measured, ccv);

    // applyCCV's own purpose (per measurement_controller.dart) is to null
    // out the measured shape; the peak that was clearly visible in the
    // deviation curve above must NOT survive as a comparable bump here.
    final peakBin =
        scmsBins.firstWhere((b) => (b.frequency - 120).abs() < 1);
    final neighborBin =
        scmsBins.firstWhere((b) => (b.frequency - 300).abs() < 1);
    expect((peakBin.magnitude - neighborBin.magnitude).abs(), lessThan(6.0),
        reason: 'scmsBins is designed to absorb the real +6dB room-mode '
            'shape, unlike the deviation curve — this is why plotting it '
            'directly produced a flat, uninformative downward line');
  });
}
