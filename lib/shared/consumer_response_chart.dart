import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/audio_analyzer.dart';

/// Consumer-facing Before/TUNAI response comparison — a simplified,
/// REW-style overlay with every technical label (Hz/dB/Q/FFT/PEQ/DSP)
/// stripped out. Renders only real, already-computed data: the measured
/// [before] curve from Room Scan and, when available, the [after] curve
/// synthesized from the actual TunePlan bands (`SpectrumSnapshotController`
/// in spectrum_snapshot.dart — no new analysis or measurement happens here).
///
/// When [after] is null (no TunePlan bands to preview, or the snapshot
/// wasn't rebuilt this session), only the Before curve is drawn — never a
/// fabricated "after" line or target curve.
class ConsumerResponseChart extends StatelessWidget {
  final List<FrequencyBin> before;
  final List<FrequencyBin>? after;
  final bool ko;

  static const double _minHz = 20;
  static const double _maxHz = 500;

  const ConsumerResponseChart({
    super.key,
    required this.before,
    this.after,
    required this.ko,
  });

  List<FrequencyBin> _inRange(List<FrequencyBin> bins) =>
      bins.where((b) => b.frequency >= _minHz && b.frequency <= _maxHz).toList()
        ..sort((a, b) => a.frequency.compareTo(b.frequency));

  /// Fractional-octave moving-average smoothing (display only — does not
  /// touch the analysis/peak-detection data upstream). A single 65536-point
  /// FFT snapshot has ~0.67Hz bin resolution, so raw bins are dominated by
  /// bin-to-bin noise; a 1/6-octave window is a standard, non-fabricating
  /// way to make the real shape (not individual noisy samples) legible —
  /// REW itself defaults to comparable smoothing for on-screen display.
  static List<FrequencyBin> _smooth(List<FrequencyBin> bins,
      {double fractionOfOctave = 1 / 6}) {
    if (bins.length < 3) return bins;
    final result = <FrequencyBin>[];
    for (final center in bins) {
      if (center.frequency <= 0) continue;
      final lo = center.frequency * math.pow(2, -fractionOfOctave / 2);
      final hi = center.frequency * math.pow(2, fractionOfOctave / 2);
      final window =
          bins.where((b) => b.frequency >= lo && b.frequency <= hi);
      final avg =
          window.map((b) => b.magnitude).reduce((a, b) => a + b) /
              window.length;
      result.add(FrequencyBin(frequency: center.frequency, magnitude: avg));
    }
    return result;
  }

  /// Log-frequency x position, normalized to [0, 1] across [_minHz, _maxHz]
  /// — a real log scale (equal screen width per octave), not a cosmetic
  /// curve transform. Axis numbers stay hidden (consumer-facing), so the
  /// underlying unit doesn't need to be user-visible.
  static double _logX(double hz) =>
      math.log(hz / _minHz) / math.log(_maxHz / _minHz);

  @override
  Widget build(BuildContext context) {
    // Only `before` gets smoothed: it's the real per-FFT-bin measured curve
    // (~0.67Hz resolution from a single 65536-point capture), dominated by
    // bin-to-bin noise without it. `after` is NOT raw data — it's already an
    // analytically smooth Gaussian synthesis on top of `before` (see
    // SpectrumSnapshotController.applyPeaks/_applyPeaksToBins), so smoothing
    // it again with the same fixed-width window was washing out real,
    // narrow-Q corrections almost entirely — a Q=15 band is only ~0.07
    // octaves wide, narrower than the 1/6-octave smoothing window, so it got
    // averaged away and the two curves ended up visually coincident (only
    // the green "after" line, drawn on top, was ever visible).
    final beforeBins = _smooth(_inRange(before));
    if (beforeBins.isEmpty) return const SizedBox.shrink();
    final afterBins = after == null ? null : _inRange(after!);

    // Generous, data-driven vertical range (never a fixed dB scale) so a
    // subtle real adjustment is still clearly visible rather than looking
    // flat against an oversized fixed range.
    final allMagnitudes = [
      ...beforeBins.map((b) => b.magnitude),
      if (afterBins != null) ...afterBins.map((b) => b.magnitude),
    ];
    final dataMin = allMagnitudes.reduce((a, b) => a < b ? a : b);
    final dataMax = allMagnitudes.reduce((a, b) => a > b ? a : b);
    final span = (dataMax - dataMin).clamp(6.0, double.infinity);
    final pad = span * 0.35;
    final minY = dataMin - pad;
    final maxY = dataMax + pad;

    const hiddenAxis = AxisTitles(sideTitles: SideTitles(showTitles: false));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: LineChart(LineChartData(
            backgroundColor: Colors.transparent,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: (maxY - minY) / 4,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: Colors.white10, strokeWidth: 0.5),
            ),
            titlesData: const FlTitlesData(
              bottomTitles: hiddenAxis,
              leftTitles: hiddenAxis,
              topTitles: hiddenAxis,
              rightTitles: hiddenAxis,
            ),
            borderData: FlBorderData(show: false),
            minX: 0,
            maxX: 1,
            minY: minY,
            maxY: maxY,
            lineBarsData: [
              LineChartBarData(
                spots: beforeBins
                    .map((b) => FlSpot(_logX(b.frequency), b.magnitude))
                    .toList(),
                isCurved: true,
                curveSmoothness: 0.2,
                // Bright enough to read as its own line even where it
                // doesn't overlap "after" — a dim 35%-alpha line at the same
                // width as a much brighter, thicker foreground line was
                // effectively invisible in practice.
                color: Colors.white.withValues(alpha: 0.6),
                barWidth: 1.8,
                dashArray: const [6, 4],
                dotData: const FlDotData(show: false),
              ),
              if (afterBins != null)
                LineChartBarData(
                  spots: afterBins
                      .map((b) => FlSpot(_logX(b.frequency), b.magnitude))
                      .toList(),
                  isCurved: true,
                  curveSmoothness: 0.2,
                  color: const Color(0xFF69F0AE),
                  barWidth: 2.2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                      show: true,
                      color: const Color(0xFF69F0AE).withValues(alpha: 0.06)),
                ),
            ],
          )),
        ),
        const SizedBox(height: 8),
        // Minimal bass/mid/treble orientation — no Hz/FFT/PEQ/Q labels, just
        // three roughly-even zones across the same log-frequency axis as the
        // curves above.
        Row(
          children: [
            Expanded(
                child: Text(ko ? '저음' : 'Bass',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10))),
            Expanded(
                child: Text(ko ? '중음' : 'Mid',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10))),
            Expanded(
                child: Text(ko ? '고음' : 'Treble',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 10))),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _LegendDot(color: Colors.white.withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Text(ko ? '현재 공간' : 'Your Space',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
            const SizedBox(width: 20),
            if (afterBins != null) ...[
              const _LegendDot(color: Color(0xFF69F0AE)),
              const SizedBox(width: 6),
              Text(ko ? 'TUNAI 예상 균형' : 'Predicted TUNAI Balance',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ],
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
