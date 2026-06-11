import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import '../../core/audio_analyzer.dart';
import '../../core/api_service.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    final bState = ref.watch(bleProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(bState: bState),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StepSection(index: 1, label: 'CONNECT', active: true,
                        child: _BlePanel(bState: bState, ref: ref)),
                    const SizedBox(height: 16),
                    _StepSection(index: 2, label: 'MEASURE',
                        active: bState.connection == BleConnectionState.connected || mState.step != MeasurementStep.idle,
                        child: _MeasurePanel(mState: mState, ref: ref)),
                    const SizedBox(height: 16),
                    _StepSection(index: 3, label: 'APPLY DSP',
                        active: mState.step == MeasurementStep.done,
                        child: _DspPanel(mState: mState, bState: bState, ref: ref)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final BleState bState;
  const _TopBar({required this.bState});

  @override
  Widget build(BuildContext context) {
    final isConnected = bState.connection == BleConnectionState.connected;
    return Consumer(builder: (context, ref, _) {
      final auth = ref.watch(authProvider);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Row(
          children: [
            const Text('TUNAI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w200, letterSpacing: 8)),
            const Spacer(),
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: isConnected ? Colors.white : Colors.white24)),
            const SizedBox(width: 8),
            Text(isConnected ? (bState.deviceName ?? 'CONNECTED') : 'NO DEVICE',
                style: TextStyle(color: isConnected ? Colors.white54 : Colors.white24, fontSize: 10, letterSpacing: 2)),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () {
                if (auth.isLoggedIn) {
                  ref.read(authProvider.notifier).logout();
                } else {
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
                }
              },
              child: Text(
                auth.isLoggedIn ? (auth.nickname ?? 'MY') : 'LOGIN',
                style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _StepSection extends StatelessWidget {
  final int index; final String label; final bool active; final Widget child;
  const _StepSection({required this.index, required this.label, required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: active ? 1.0 : 0.35,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: active ? Colors.white24 : Colors.white12), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Text('0$index', style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 11, fontWeight: FontWeight.w300, letterSpacing: 1)),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: active ? Colors.white60 : Colors.white24, fontSize: 10, letterSpacing: 3)),
            ])),
          const SizedBox(height: 16),
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: child),
        ]),
      ),
    );
  }
}

class _BlePanel extends StatelessWidget {
  final BleState bState; final WidgetRef ref;
  const _BlePanel({required this.bState, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isScanning = bState.connection == BleConnectionState.scanning || bState.connection == BleConnectionState.connecting;
    final isConnected = bState.connection == BleConnectionState.connected;
    return Row(children: [
      Expanded(child: Text(bState.message.isEmpty ? 'TUNAI 스피커를 검색합니다.' : bState.message,
          style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5))),
      const SizedBox(width: 16),
      _OutlineButton(
        label: isConnected ? 'DISCONNECT' : isScanning ? 'SCANNING...' : 'SCAN',
        loading: isScanning,
        onTap: isScanning ? null : isConnected
            ? () => ref.read(bleProvider.notifier).disconnect()
            : () => ref.read(bleProvider.notifier).scanAndConnect(),
      ),
    ]);
  }
}

class _MeasurePanel extends StatelessWidget {
  final MeasurementState mState; final WidgetRef ref;
  const _MeasurePanel({required this.mState, required this.ref});

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(measurementProvider.notifier);
    final step = mState.step;
    final isRunning = step != MeasurementStep.idle && step != MeasurementStep.done && step != MeasurementStep.error;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(
          mState.error ?? (mState.message.isEmpty ? '핑크노이즈 재생 후 공간 음향을 분석합니다.' : mState.message),
          style: TextStyle(color: mState.error != null ? Colors.redAccent : Colors.white38, fontSize: 13, height: 1.5))),
        const SizedBox(width: 16),
        _OutlineButton(
          label: isRunning ? '측정 중...' : step == MeasurementStep.done ? 'RE-MEASURE' : 'MEASURE',
          loading: isRunning,
          onTap: isRunning ? null : step == MeasurementStep.done || step == MeasurementStep.error ? ctrl.reset : ctrl.startMeasurement,
        ),
      ]),
      if (mState.scmsBins.isNotEmpty) ...[const SizedBox(height: 20), _SpectrumChart(bins: mState.scmsBins, peaks: mState.peaks)],
      if (mState.peaks.isNotEmpty) ...[const SizedBox(height: 16), _PeakTable(peaks: mState.peaks)],
    ]);
  }
}

class _DspPanel extends StatelessWidget {
  final MeasurementState mState; final BleState bState; final WidgetRef ref;
  const _DspPanel({required this.mState, required this.bState, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isConnected = bState.connection == BleConnectionState.connected;
    final isSending = bState.isSending;
    final hasDsp = mState.packets.isNotEmpty;
    final hint = !hasDsp ? '측정 후 DSP 필터가 생성됩니다.' : !isConnected ? '스피커를 연결하면 DSP를 적용할 수 있습니다.' : '${mState.packets.length}개 노치 필터 → ADAU1701 Safeload';
    return Row(children: [
      Expanded(child: Text(isSending ? bState.message : hint, style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5))),
      const SizedBox(width: 16),
      _OutlineButton(label: isSending ? 'SENDING...' : 'APPLY', loading: isSending, enabled: hasDsp && isConnected && !isSending,
          onTap: hasDsp && isConnected && !isSending ? () => ref.read(bleProvider.notifier).sendPackets(mState.packets) : null),
    ]);
  }
}

void _showShareDialog(BuildContext context, MeasurementState mState) {
  final titleCtrl = TextEditingController();
  final roomCtrl = TextEditingController();
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF111111),
      title: const Text('프리셋 공유', style: TextStyle(color: Colors.white, fontSize: 16, letterSpacing: 2)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('측정된 DSP 필터를 커뮤니티에 공유합니다.',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'TITLE',
              labelStyle: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: roomCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'ROOM TAG (예: 6평 거실)',
              labelStyle: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 2),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            final fps = mState.peaks.map((p) => {
              'f': p.frequency, 'g': p.gain, 'q': p.q
            }).toList();
            final res = await ApiService.uploadPreset(
              title: titleCtrl.text.trim().isEmpty ? '내 공간 튜닝' : titleCtrl.text.trim(),
              description: '${mState.peaks.length}개 공진 주파수 보정',
              fps: fps,
              roomTag: roomCtrl.text.trim(),
            );
            if (res['status'] == 'ok') {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('프리셋이 공유됐습니다! 커뮤니티에서 확인하세요.')));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('로그인 후 공유할 수 있습니다.')));
            }
          },
          child: const Text('공유', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}

class _OutlineButton extends StatelessWidget {
  final String label; final VoidCallback? onTap; final bool loading; final bool enabled;
  const _OutlineButton({required this.label, this.onTap, this.loading = false, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final active = onTap != null && enabled && !loading;
    return GestureDetector(
      onTap: active ? onTap : null,
      child: Container(
        height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(border: Border.all(color: active ? Colors.white : Colors.white24), borderRadius: BorderRadius.circular(6)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (loading) ...[const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1, color: Colors.white38)), const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w300)),
        ]),
      ),
    );
  }
}

class _SpectrumChart extends StatelessWidget {
  final List<FrequencyBin> bins; final List<ResonancePeak> peaks;
  const _SpectrumChart({required this.bins, required this.peaks});

  @override
  Widget build(BuildContext context) {
    final displayBins = bins.where((b) => b.frequency >= 20 && b.frequency <= 500).toList();
    if (displayBins.isEmpty) return const SizedBox.shrink();
    final spots = displayBins.map((b) => FlSpot(b.frequency, b.magnitude.clamp(-60.0, 20.0))).toList();
    return SizedBox(
      height: 160,
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
          lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.white60, barWidth: 1.2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.white.withOpacity(0.04)))],
          extraLinesData: ExtraLinesData(verticalLines: peaks.map((p) => VerticalLine(x: p.frequency, color: Colors.redAccent.withOpacity(0.5), strokeWidth: 1, dashArray: [3, 4],
            label: VerticalLineLabel(show: true, labelResolver: (l) => '${p.frequency.toStringAsFixed(0)}', style: const TextStyle(color: Colors.redAccent, fontSize: 8)))).toList()),
        )),
        const Positioned(top: 0, left: 0, child: Text('Scms  20–500 Hz', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1))),
      ]),
    );
  }
}

class _PeakTable extends StatelessWidget {
  final List<ResonancePeak> peaks;
  const _PeakTable({required this.peaks});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const Padding(padding: EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Expanded(child: Text('FREQ', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2))),
          SizedBox(width: 72, child: Text('GAIN', textAlign: TextAlign.right, style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2))),
          SizedBox(width: 56, child: Text('Q', textAlign: TextAlign.right, style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2))),
        ])),
      ...peaks.map((p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 10), decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
          Expanded(child: Text('${p.frequency.toStringAsFixed(1)} Hz', style: const TextStyle(color: Colors.white, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]))),
          SizedBox(width: 72, child: Text('${p.gain.toStringAsFixed(1)} dB', textAlign: TextAlign.right, style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
          SizedBox(width: 56, child: Text(p.q.toStringAsFixed(1), textAlign: TextAlign.right, style: const TextStyle(color: Colors.white38, fontSize: 13))),
        ]),
      )),
    ]);
  }
}