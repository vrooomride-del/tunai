import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'audio_analyzer.dart';

/// One broadband tonal correction: a wide, gentle filter that pulls a whole
/// region of the spectrum back toward the measurement's own local trend.
///
/// Deliberately NOT a [ResonancePeak] — a resonance is a narrow physical room
/// mode to be cut, whereas this is a broad tonal imbalance that may need
/// either a cut OR a small boost.
@immutable
class ToneCorrection {
  final double frequencyHz;
  final double gainDb;
  final double q;

  /// How far the measured region sat from its local trend, before clamping.
  /// Kept for logging/diagnostics so a clamped correction is distinguishable
  /// from one that fit inside the limits.
  final double measuredDeviationDb;

  const ToneCorrection({
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.measuredDeviationDb,
  });

  @override
  String toString() => 'ToneCorrection(${frequencyHz.toStringAsFixed(0)}Hz, '
      '${gainDb.toStringAsFixed(1)}dB, Q${q.toStringAsFixed(2)}, '
      'dev=${measuredDeviationDb.toStringAsFixed(1)}dB)';
}

/// Derives broadband tonal corrections across the FULL audible range, rather
/// than only hunting narrow room modes below 300Hz.
///
/// WHY THIS EXISTS — the three things a room correction can fix, ordered by
/// how much a listener actually hears them:
///
///   1. Broad tonal balance (is the whole low/mid/high region too loud or too
///      quiet relative to its neighbours) — largest audible effect, and the
///      most robust to measure, because each region averages hundreds of FFT
///      bins.
///   2. Room gain near walls/corners — a broad lift, same robustness.
///   3. Individual narrow room modes — smallest audible effect, and by far the
///      least reliable: they move with microphone position and, at Room Scan's
///      bin resolution, are only 1-2 bins wide.
///
/// [AudioAnalyzer.detectPeaks] does (3) exclusively. Real-device captures of
/// the same room minutes apart returned almost entirely different "resonances"
/// each time — the expected outcome of chasing 1-2 bin features. This analyzer
/// does (1) and (2), which is what makes an audible, repeatable difference.
///
/// SELF-REFERENCED TARGET — no calibration data required, and none invented.
/// An uncalibrated phone microphone has its own fixed frequency response, and
/// from a single capture there is no way to separate it from the room. So this
/// deliberately does NOT compare against any absolute target curve, which
/// would require calibration this app does not have. Instead each 1/3-octave
/// region is compared against the measurement's OWN one-octave-smoothed trend.
/// Broad tilt shared by the microphone, the speaker's voicing and the target
/// preference cancels out; what remains is the local peaks and dips that a
/// room actually imposes. Absolute-target matching belongs to the Pro tier,
/// where a calibrated measurement microphone makes it meaningful.
class BroadbandToneAnalyzer {
  /// Analysis range. The bottom is set by what a phone microphone can be
  /// trusted to hear (below ~60Hz they roll off steeply and often carry a
  /// high-pass filter); the top by where a phone microphone's response
  /// becomes too variable to act on.
  static const double minFrequencyHz = 60;
  static const double maxFrequencyHz = 8000;

  /// One correction per region, matching the DSP's real 3-band budget
  /// (`DspCapability.consumerAdau1701.maxDeployableBands`). Regions are split
  /// roughly by octave span so the three corrections cannot clump together
  /// and leave two-thirds of the spectrum untouched.
  static const List<({double lowHz, double highHz})> regions = [
    (lowHz: 60, highHz: 300),
    (lowHz: 300, highHz: 1500),
    (lowHz: 1500, highHz: 8000),
  ];

  /// Q of the emitted corrections — about one octave wide. Broad on purpose:
  /// the goal is to shift a region's overall level, not to notch a feature,
  /// and a wide filter is far less sensitive to the exact centre frequency
  /// being slightly off.
  static const double correctionQ = 1.0;

  /// Below this, the region is treated as already balanced. Set above the
  /// run-to-run spread seen on real captures so normal measurement variation
  /// can never manufacture a correction.
  static const double minimumDeviationDb = 2.5;

  /// Asymmetric on purpose: cutting is safe (it only removes energy), while
  /// boosting costs amplifier headroom and excursion. Matches what the
  /// deployment protocol itself accepts (gain -6..+3dB).
  static const double maximumCutDb = 6;
  static const double maximumBoostDb = 3;

  /// 1/3-octave analysis bands; the trend is fitted over a much wider window.
  ///
  /// The window MUST be substantially wider than the features being
  /// corrected, or the trend simply follows the bump and cancels the very
  /// deviation it is meant to expose — with a one-octave window an 8dB
  /// tonal hump reads as under 1dB of deviation.
  static const double _bandsPerOctave = 3;
  static const double _trendWindowOctaves = 3.0;

  /// Returns at most one correction per region, in ascending frequency.
  /// Returns an empty list when [bins] carries too little usable data to
  /// judge — never a fabricated "balanced" result.
  static List<ToneCorrection> analyze(List<FrequencyBin> bins) {
    if (bins.length < 2) return const [];

    final centers = _bandCenters();
    final levels = <double, double>{};
    for (final fc in centers) {
      final level = _bandLevel(bins, fc);
      if (level != null) levels[fc] = level;
    }
    // Needs enough populated bands for a one-octave trend to mean anything.
    if (levels.length < _bandsPerOctave * 2) {
      debugPrint('[TONE] too few usable analysis bands '
          '(${levels.length}) — no broadband correction');
      return const [];
    }

    final deviations = <double, double>{};
    for (final entry in levels.entries) {
      final trend = _trendAt(levels, entry.key);
      if (trend != null) deviations[entry.key] = entry.value - trend;
    }

    final corrections = <ToneCorrection>[];
    for (final region in regions) {
      final inRegion = deviations.entries
          .where((e) => e.key >= region.lowHz && e.key < region.highHz)
          .toList();
      if (inRegion.isEmpty) continue;

      // The single most out-of-balance band in this region.
      inRegion.sort((a, b) => b.value.abs().compareTo(a.value.abs()));
      final worst = inRegion.first;
      if (worst.value.abs() < minimumDeviationDb) {
        debugPrint('[TONE] region ${region.lowHz.toStringAsFixed(0)}-'
            '${region.highHz.toStringAsFixed(0)}Hz balanced '
            '(max dev ${worst.value.toStringAsFixed(1)}dB) — no correction');
        continue;
      }

      // Correct against the deviation: a region above its trend gets cut, one
      // below gets a (smaller) boost.
      final gain = (-worst.value).clamp(-maximumCutDb, maximumBoostDb);
      corrections.add(ToneCorrection(
        frequencyHz: worst.key,
        gainDb: gain.toDouble(),
        q: correctionQ,
        measuredDeviationDb: worst.value,
      ));
    }

    corrections.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    debugPrint('[TONE] broadband corrections=${corrections.length} '
        '${corrections.map((c) => c.toString()).toList()}');
    return corrections;
  }

  /// 1/3-octave centres spanning the analysis range.
  static List<double> _bandCenters() {
    final centers = <double>[];
    final step = math.pow(2, 1 / _bandsPerOctave).toDouble();
    for (var fc = minFrequencyHz; fc <= maxFrequencyHz; fc *= step) {
      centers.add(fc);
    }
    return centers;
  }

  /// Mean magnitude across one 1/3-octave band. Null when the band contains
  /// no bins at all (spectrum does not reach that far).
  static double? _bandLevel(List<FrequencyBin> bins, double centerHz) {
    final halfBand = math.pow(2, 1 / (2 * _bandsPerOctave)).toDouble();
    final low = centerHz / halfBand;
    final high = centerHz * halfBand;
    var sum = 0.0;
    var count = 0;
    for (final bin in bins) {
      if (bin.frequency < low) continue;
      if (bin.frequency > high) break;
      if (!bin.magnitude.isFinite) continue;
      sum += bin.magnitude;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  /// The "local trend" a band is judged against: a straight line fitted, in
  /// log-frequency, to the band levels within [_trendWindowOctaves] around it,
  /// evaluated at the band itself.
  ///
  /// A local LINE rather than a local average, specifically so that a steady
  /// tilt produces exactly zero deviation everywhere — including at the top
  /// and bottom of the analysed range, where the window is necessarily
  /// one-sided and a moving average would read the tilt as a bump and
  /// "correct" it. That matters because the biggest tilt in an uncalibrated
  /// measurement is the microphone's own response, which must never be
  /// treated as something the room did.
  ///
  /// Null when the window holds too few bands to fit a line meaningfully.
  static double? _trendAt(Map<double, double> levels, double centerHz) {
    final halfWindow = math.pow(2, _trendWindowOctaves / 2).toDouble();
    final low = centerHz / halfWindow;
    final high = centerHz * halfWindow;

    // Least-squares fit of y = a + b*x, with x in octaves relative to the
    // band being evaluated, so the fitted value at the band is simply `a`.
    var n = 0;
    var sumX = 0.0, sumY = 0.0, sumXX = 0.0, sumXY = 0.0;
    for (final entry in levels.entries) {
      if (entry.key < low || entry.key > high) continue;
      final x = math.log(entry.key / centerHz) / math.ln2;
      final y = entry.value;
      n++;
      sumX += x;
      sumY += y;
      sumXX += x * x;
      sumXY += x * y;
    }
    if (n < 5) return null;

    final denominator = n * sumXX - sumX * sumX;
    if (denominator.abs() < 1e-12) return sumY / n;
    final slope = (n * sumXY - sumX * sumY) / denominator;
    final intercept = (sumY - slope * sumX) / n;
    return intercept;
  }
}
