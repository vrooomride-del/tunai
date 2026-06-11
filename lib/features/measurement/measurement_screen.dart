import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../measurement/measurement_controller.dart';
import '../../core/audio_analyzer.dart';

class MeasurementScreen extends ConsumerWidget {
  const MeasurementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(measurementProvider);
    final ctrl = ref.read(measurementProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(
          'TUNAI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w300,
            letterSpacing: 6,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 상태 표시
            _StatusCard(state: state),
            const SizedBox(height: 24),

            // 주파수 응답 그래프
            if (state.scmsBins.isNotEmpty) ...[
              _SpectrumChart(bins: state.scmsBins, peaks: state.peaks),
              const SizedBox(height: 24),
            ],

            // 검출된 피크 목록
            if (state.peaks.isNotEmpty) ...[
              _PeakList(peaks: state.peaks),
              const SizedBox(height: 24),
            ],

            const Spacer(),

            // 측정 버튼
            _MeasureButton(state: state, ctrl: ctrl),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final MeasurementState state;
  const _StatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final isRunning = state.step != MeasurementStep.idle &&
        state.step != MeasurementStep.done &&
        state.step != MeasurementStep.error;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (isRunning)
            const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 1,
            )
          else
            Icon(
              state.step == MeasurementStep.done
                  ? Icons.check_circle_outline
                  : state.step == MeasurementStep.error
                      ? Icons.error_outline
                      : Icons.speaker,
              color: Colors.white54,
              size: 40,
            ),
          const SizedBox(height: 16),
          Text(
            state.error ?? state.message.ifEmpty('공간 음향 측정 준비'),
            style: const TextStyle(color: Colors.white70, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SpectrumChart extends StatelessWidget {
  final List<FrequencyBin> bins;
  final List<ResonancePeak> peaks;
  const _SpectrumChart({required this.bins, required this.peaks});

  @override
  Widget build(BuildContext context) {
    // 20~500Hz 범위만 표시
    final displayBins = bins
        .where((b) => b.frequency >= 20 && b.frequency <= 500)
        .toList();

    if (displayBins.isEmpty) return const SizedBox.shrink();

    final spots = displayBins
        .map((b) => FlSpot(b.frequency, b.magnitude.clamp(-60.0, 20.0)))
        .toList();

    // 피크 위치 표시
    final peakSpots = peaks
        .map((p) => FlSpot(p.frequency, p.gain.abs() + 5))
        .toList();

    return Container(
      height: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'FREQUENCY RESPONSE (Scms) — 20~500Hz',
            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                backgroundColor: Colors.transparent,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      const FlLine(color: Colors.white10, strokeWidth: 0.5),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 100,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}',
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 20,
                      getTitlesWidget: (v, _) => Text(
                        '${v.toInt()}',
                        style: const TextStyle(color: Colors.white38, fontSize: 9),
                      ),
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 20,
                maxX: 500,
                minY: -60,
                maxY: 20,
                lineBarsData: [
                  // Scms 스펙트럼
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: Colors.white70,
                    barWidth: 1.5,
                    dotData: const FlDotData(show: false),
                  ),
                ],
                // 피크 마커
                extraLinesData: ExtraLinesData(
                  verticalLines: peaks.map((p) => VerticalLine(
                    x: p.frequency,
                    color: Colors.redAccent.withOpacity(0.6),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                    label: VerticalLineLabel(
                      show: true,
                      labelResolver: (line) => '${p.frequency.toStringAsFixed(0)}Hz',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 8),
                    ),
                  )).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PeakList extends StatelessWidget {
  final List<ResonancePeak> peaks;
  const _PeakList({required this.peaks});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DETECTED RESONANCE PEAKS',
            style: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
          ),
          const SizedBox(height: 12),
          ...peaks.map((p) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${p.frequency.toStringAsFixed(1)} Hz',
                  style: const TextStyle(color: Colors.white, fontSize: 14,
                      fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const Spacer(),
                Text(
                  '${p.gain.toStringAsFixed(1)} dB',
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
                const SizedBox(width: 16),
                Text(
                  'Q ${p.q.toStringAsFixed(1)}',
                  style: const TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _MeasureButton extends StatelessWidget {
  final MeasurementState state;
  final MeasurementController ctrl;
  const _MeasureButton({required this.state, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isRunning = state.step != MeasurementStep.idle &&
        state.step != MeasurementStep.done &&
        state.step != MeasurementStep.error;

    return GestureDetector(
      onTap: isRunning ? null : () {
        if (state.step == MeasurementStep.done ||
            state.step == MeasurementStep.error) {
          ctrl.reset();
        } else {
          ctrl.startMeasurement();
        }
      },
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          border: Border.all(
            color: isRunning ? Colors.white24 : Colors.white,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            isRunning
                ? '측정 중...'
                : state.step == MeasurementStep.done
                    ? '다시 측정'
                    : '공간 측정 시작',
            style: TextStyle(
              color: isRunning ? Colors.white38 : Colors.white,
              fontSize: 16,
              letterSpacing: 2,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
