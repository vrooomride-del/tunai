import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/audio_analyzer.dart';
import '../../core/spectrum_snapshot.dart';
import '../../main.dart' show currentTabIndexProvider;
import '../../shared/widgets.dart';
import '../../shared/spectrum_chart.dart';
import '../../shared/preset_bar.dart';
import '../dsp/master_volume_controller.dart';

/// main.dart의 screens 리스트 순서상 LISTEN 탭의 인덱스 — 다른 탭으로 이동하면
/// Loop를 자동 정지하기 위해 필요
const _kListenTabIndex = 3;

/// LISTEN 탭 — Before/After A/B 비교 + 3색 스펙트럼 오버레이.
/// "와... 진짜 달라졌네"를 사용자가 직접 느끼게 하는 화면.
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});
  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> {
  bool _showAfter = true;
  bool _loop = false;
  Timer? _timer;

  // Before/After 각각 이만큼 보여준 뒤 자동 전환 (요청: 1.5초씩)
  static const _loopInterval = Duration(milliseconds: 1500);

  void _setLoop(bool v) {
    setState(() => _loop = v);
    _timer?.cancel();
    if (v) {
      _timer = Timer.periodic(_loopInterval, (_) {
        setState(() => _showAfter = !_showAfter);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = ref.watch(spectrumSnapshotProvider);
    final hasBefore = snap.before != null;
    final hasAfter = snap.afterAi != null;

    // 다른 탭으로 이동하면 Loop 자동 정지 — IndexedStack은 이 화면을 dispose하지
    // 않으므로 currentTabIndexProvider로 탭 이탈을 감지해야 한다.
    ref.listen<int>(currentTabIndexProvider, (prev, next) {
      if (next != _kListenTabIndex && _loop) _setLoop(false);
    });

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'LISTEN'),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 24), child: PresetBar()),
            const SizedBox(height: 4),
            const _MasterVolumeSection(),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: !hasBefore
                    ? const _EmptyState()
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _AbToggle(
                          showAfter: _showAfter,
                          loop: _loop,
                          hasAfter: hasAfter,
                          onSelect: hasAfter ? (v) => setState(() { _showAfter = v; _setLoop(false); }) : null,
                          onLoopChanged: hasAfter ? _setLoop : null,
                        ),
                        const SizedBox(height: 12),
                        SectionCard(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Text(_showAfter && hasAfter ? 'AFTER (AI 적용)' : 'BEFORE (원본 측정)',
                                style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
                            const SizedBox(height: 8),
                            SpectrumChart(
                              bins: (_showAfter && hasAfter ? snap.afterAi : snap.before) ?? const [],
                              peaks: const [],
                            ),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        const Text('그래프 3색 오버레이', style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2)),
                        const SizedBox(height: 8),
                        SectionCard(child: _OverlayChart(snap: snap)),
                        const SizedBox(height: 8),
                        const _Legend(),
                      ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Master Volume ─────────────────────────────────────────────

class _MasterVolumeSection extends ConsumerWidget {
  const _MasterVolumeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vol = ref.watch(masterVolumeProvider);
    final ctrl = ref.read(masterVolumeProvider.notifier);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('MASTER VOL',
                  style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 3)),
              const SizedBox(width: 12),
              Text('${vol.toStringAsFixed(1)} dB',
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
              const Spacer(),
              for (final db in [-60.0, -50.0, -40.0]) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => ctrl.setVolume(db),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: vol == db ? Colors.white54 : Colors.white24, width: 0.5),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text('${db.toInt()}',
                        style: TextStyle(
                          color: vol == db ? Colors.white70 : Colors.white38,
                          fontSize: 10, letterSpacing: 1,
                        )),
                  ),
                ),
              ],
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 1.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: Colors.white54,
              inactiveTrackColor: Colors.white12,
              thumbColor: Colors.white,
              overlayColor: Colors.white12,
            ),
            child: Slider(
              value: vol,
              min: -70, max: 0,
              onChanged: (v) => ctrl.updateUiOnly(v),
              onChangeEnd: (v) => ctrl.setVolume(v),
            ),
          ),
          // ── Test Tone ────────────────────────────────────────────────────
          GestureDetector(
            onTap: () {
              // TODO: tone_generator.dart 연동 (1kHz sine)
            },
            child: Container(
              height: 34,
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.music_note_outlined, color: Colors.white38, size: 14),
                  SizedBox(width: 8),
                  Text('1 kHz TEST TONE',
                      style: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return const SectionCard(
      child: Column(children: [
        Icon(Icons.graphic_eq, color: Colors.white24, size: 32),
        SizedBox(height: 10),
        Text('MEASURE에서 측정을 완료하면 Before/After 비교가 여기에 표시됩니다',
            style: TextStyle(color: Colors.white54, fontSize: 13), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _AbToggle extends StatelessWidget {
  final bool showAfter;
  final bool loop;
  final bool hasAfter;
  final ValueChanged<bool>? onSelect;
  final ValueChanged<bool>? onLoopChanged;
  const _AbToggle({required this.showAfter, required this.loop, required this.hasAfter, this.onSelect, this.onLoopChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: Row(children: [
          Expanded(child: _AbButton(label: 'BEFORE', selected: !showAfter, onTap: onSelect == null ? null : () => onSelect!(false))),
          const SizedBox(width: 8),
          Expanded(child: _AbButton(label: 'AFTER', selected: showAfter, enabled: hasAfter, onTap: onSelect == null ? null : () => onSelect!(true))),
        ]),
      ),
      const SizedBox(width: 12),
      GestureDetector(
        onTap: onLoopChanged == null ? null : () => onLoopChanged!(!loop),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: loop ? Colors.white : Colors.white24),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Icon(loop ? Icons.pause_circle_outline : Icons.play_circle_outline,
                color: loop ? Colors.white : Colors.white38, size: 14),
            const SizedBox(width: 4),
            Text('LOOP', style: TextStyle(color: loop ? Colors.white : Colors.white38, fontSize: 10, letterSpacing: 1)),
          ]),
        ),
      ),
    ]);
  }
}

class _AbButton extends StatelessWidget {
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
  const _AbButton({required this.label, required this.selected, this.enabled = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: selected && active ? Colors.white : Colors.white24),
          borderRadius: BorderRadius.circular(6),
          color: selected && active ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Text(label,
            style: TextStyle(color: !active ? Colors.white12 : selected ? Colors.white : Colors.white54, fontSize: 12, letterSpacing: 2)),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();
  @override
  Widget build(BuildContext context) {
    return const Row(children: [
      _LegendDot(color: Colors.white38, label: 'Before (원본)'),
      SizedBox(width: 16),
      _LegendDot(color: Colors.greenAccent, label: 'After (AI 적용)'),
      SizedBox(width: 16),
      _LegendDot(color: Colors.lightBlueAccent, label: '현재'),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ]);
  }
}

/// 회색(Before) · 초록(After AI) · 파랑(현재) 3색 오버레이
class _OverlayChart extends StatelessWidget {
  final SpectrumSnapshot snap;
  const _OverlayChart({required this.snap});

  List<FlSpot> _spotsOf(List<FrequencyBin>? bins) {
    if (bins == null) return const [];
    return bins
        .where((b) => b.frequency >= 20 && b.frequency <= 500)
        .map((b) => FlSpot(b.frequency, b.magnitude.clamp(-60.0, 20.0)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final beforeSpots = _spotsOf(snap.before);
    final afterSpots = _spotsOf(snap.afterAi);
    final currentSpots = _spotsOf(snap.current);
    if (beforeSpots.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 260,
      child: LineChart(LineChartData(
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
        lineBarsData: [
          LineChartBarData(spots: beforeSpots, isCurved: true, color: Colors.white38, barWidth: 1.2, dotData: const FlDotData(show: false)),
          if (afterSpots.isNotEmpty)
            LineChartBarData(spots: afterSpots, isCurved: true, color: Colors.greenAccent, barWidth: 1.2, dotData: const FlDotData(show: false)),
          if (currentSpots.isNotEmpty)
            LineChartBarData(spots: currentSpots, isCurved: true, color: Colors.lightBlueAccent, barWidth: 1.0, dotData: const FlDotData(show: false)),
        ],
      )),
    );
  }
}
