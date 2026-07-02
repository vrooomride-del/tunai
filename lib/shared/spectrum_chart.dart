import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/audio_analyzer.dart';

/// 20-500Hz 단일 스펙트럼 라인 차트 (기존 home_screen.dart의 _SpectrumChart 추출)
class SpectrumChart extends StatelessWidget {
  final List<FrequencyBin> bins;
  final List<ResonancePeak> peaks;
  const SpectrumChart({super.key, required this.bins, required this.peaks});

  @override
  Widget build(BuildContext context) {
    final displayBins = bins.where((b) => b.frequency >= 20 && b.frequency <= 500).toList();
    if (displayBins.isEmpty) return const SizedBox.shrink();
    final spots = displayBins.map((b) => FlSpot(b.frequency, b.magnitude.clamp(-60.0, 20.0))).toList();
    return SizedBox(
      height: 280,
      child: Stack(children: [
        LineChart(LineChartData(
          backgroundColor: Colors.transparent,
          gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => const FlLine(color: Colors.white10, strokeWidth: 0.5)),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 100, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white24, fontSize: 9)))),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: 20, getTitlesWidget: (v, _) => Text('${v.toInt()}', style: const TextStyle(color: Colors.white24, fontSize: 9)))),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          minX: 20, maxX: 500, minY: -60, maxY: 20,
          lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.white60, barWidth: 1.2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.white.withValues(alpha: 0.04)))],
          extraLinesData: ExtraLinesData(verticalLines: peaks.map((p) => VerticalLine(x: p.frequency, color: Colors.redAccent.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [3, 4],
            label: VerticalLineLabel(show: true, labelResolver: (l) => p.frequency.toStringAsFixed(0), style: const TextStyle(color: Colors.redAccent, fontSize: 8)))).toList()),
        )),
        const Positioned(top: 0, left: 0, child: Text('Scms  20–500 Hz', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1))),
      ]),
    );
  }
}

/// 측정된 공진 주파수 테이블 (기존 home_screen.dart의 _PeakTable 추출)
class PeakTable extends StatelessWidget {
  final List<ResonancePeak> peaks;
  const PeakTable({super.key, required this.peaks});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Padding(padding: EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text('FREQ', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2))),
          SizedBox(width: 80, child: Text('GAIN', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2))),
          SizedBox(width: 60, child: Text('Q', textAlign: TextAlign.right, style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 2))),
        ])),
      ...peaks.map((p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 5, height: 5, margin: const EdgeInsets.only(right: 10), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
          Expanded(child: Text('${p.frequency.toStringAsFixed(1)} Hz', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()]))),
          SizedBox(width: 80, child: Text('${p.gain.toStringAsFixed(1)} dB', textAlign: TextAlign.right, style: const TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.w500))),
          SizedBox(width: 60, child: Text(p.q.toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white60, fontSize: 15))),
        ]),
      )),
    ]);
  }
}
