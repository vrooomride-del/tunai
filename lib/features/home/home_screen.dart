import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_screen.dart';
import '../../core/audio_analyzer.dart';
import '../../core/ai_tuning_service.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/speaker_profile.dart';
import '../dsp/dsp_compiler.dart';

// systemProfileProvider, speakerProfileProvider는 core에서 import됨
// (community_screen 등 다른 feature에서 순환 없이 접근 가능)

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
                    _StepSection(index: 1, label: 'SELECT SPEAKER', active: true,
                        child: _SpeakerSelectPanel(ref: ref)),
                    const SizedBox(height: 16),
                    _StepSection(index: 2, label: 'CONNECT', active: true,
                        child: _BlePanel(bState: bState, ref: ref)),
                    const SizedBox(height: 16),
                    _StepSection(index: 3, label: 'MEASURE',
                        active: bState.connection == BleConnectionState.connected || mState.step != MeasurementStep.idle,
                        child: _MeasurePanel(mState: mState, ref: ref)),
                    const SizedBox(height: 16),
                    _StepSection(index: 4, label: 'APPLY DSP',
                        active: mState.step == MeasurementStep.done,
                        child: _DspPanel(mState: mState, bState: bState, ref: ref)),
                    const SizedBox(height: 16),
                    _StepSection(index: 5, label: 'AI TUNE',
                        active: mState.step == MeasurementStep.done,
                        child: _AiTunePanel(mState: mState, ref: ref)),
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

class _SpeakerSelectPanel extends StatelessWidget {
  final WidgetRef ref;
  const _SpeakerSelectPanel({required this.ref});

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(systemProfileProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...kAllSystemProfiles.map((profile) {
          final isSelected = profile.id == selected.id;
          return GestureDetector(
            onTap: () => ref.read(systemProfileProvider.notifier).state = profile,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: isSelected ? Colors.white : Colors.white12),
                borderRadius: BorderRadius.circular(6),
                color: isSelected ? Colors.white.withValues(alpha: 0.05) : Colors.transparent,
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile.displayName,
                      style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 12, letterSpacing: 1.5)),
                  const SizedBox(height: 2),
                  Text(profile.description,
                      style: const TextStyle(color: Colors.white30, fontSize: 10)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(profile.chipLabel,
                      style: const TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, color: Colors.white, size: 14),
                ],
              ]),
            ),
          );
        }),
        const SizedBox(height: 4),
        Consumer(builder: (_, r, __) {
          final p = r.watch(systemProfileProvider);
          return Text(
            '${p.channelCount}ch · 크로스오버 ${p.crossoverPoints}개',
            style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
          );
        }),
      ],
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
          onTap: isRunning ? null : step == MeasurementStep.done || step == MeasurementStep.error
            ? ctrl.reset
            : () => ctrl.startMeasurement(speakerProfile: ref.read(speakerProfileProvider)),
        ),
      ]),
      if (kDebugMode) ...[
        const SizedBox(height: 12),
        _OutlineButton(
          label: '🛠 더미 데이터 주입',
          onTap: () => ctrl.injectDummyData(),
        ),
      ],
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
    final profile = ref.watch(systemProfileProvider);
    final chipHint = profile.isAdau1466 ? '${profile.chipLabel} — SigmaStudio 주소맵 미확정' : '${mState.packets.length}개 노치 필터 → ${profile.chipLabel} Safeload';
    final hint = !hasDsp ? '측정 후 DSP 필터가 생성됩니다.' : !isConnected ? '스피커를 연결하면 DSP를 적용할 수 있습니다.' : chipHint;
    final canApply = hasDsp && isConnected && !isSending && !profile.isAdau1466;
    return Row(children: [
      Expanded(child: Text(isSending ? bState.message : hint, style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.5))),
      const SizedBox(width: 16),
      _OutlineButton(label: isSending ? 'SENDING...' : 'APPLY', loading: isSending, enabled: canApply,
          onTap: canApply ? () {
            final sp = ref.read(speakerProfileProvider);
            final packets = [
              if (sp != null) DspCompiler.compileHpf(sp.recommendedHpfFreq),
              ...mState.packets,
            ];
            debugPrint('[DSP] APPLY: HPF=${sp != null ? '${sp.recommendedHpfFreq.toStringAsFixed(0)}Hz' : 'none'}, PEQ=${mState.packets.length}개');
            ref.read(bleProvider.notifier).sendPackets(packets);
          } : null),
    ]);
  }
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
          lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.white60, barWidth: 1.2, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.white.withValues(alpha: 0.04)))],
          extraLinesData: ExtraLinesData(verticalLines: peaks.map((p) => VerticalLine(x: p.frequency, color: Colors.redAccent.withValues(alpha: 0.5), strokeWidth: 1, dashArray: [3, 4],
            label: VerticalLineLabel(show: true, labelResolver: (l) => p.frequency.toStringAsFixed(0), style: const TextStyle(color: Colors.redAccent, fontSize: 8)))).toList()),
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
class _AiTunePanel extends StatefulWidget {
  final MeasurementState mState;
  final WidgetRef ref;
  const _AiTunePanel({required this.mState, required this.ref});
  @override
  State<_AiTunePanel> createState() => _AiTunePanelState();
}

class _AiTunePanelState extends State<_AiTunePanel> {
  bool _loading = false;
  bool _applying = false;
  AiTuningResult? _result;
  final _ctrl = TextEditingController(text: '자연스럽고 균형잡힌 소리로 튜닝해줘');

  Future<void> _suggest() async {
    setState(() { _loading = true; _result = null; });
    final result = await AiTuningService.suggest(
      peaks: widget.mState.peaks,
      userRequest: _ctrl.text,
    );
    setState(() { _loading = false; _result = result; });
  }

  Future<void> _applyBand(Map<String, dynamic> band, int idx) async {
    if (band['enabled'] == false) return;
    final peak = ResonancePeak(
      frequency: (band['frequency'] as num).toDouble(),
      gain: (band['gainDb'] as num).toDouble(),
      q: (band['q'] as num).toDouble(),
    );
    final packet = DspCompiler.compilePeak(peak, DspCompiler.peqStartPramAddr + idx * 5);
    await widget.ref.read(bleProvider.notifier).sendPackets([packet]);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Band ${idx + 1} 전송 완료'),
        duration: const Duration(seconds: 1),
      ));
    }
  }

  Future<void> _applyAll() async {
    if (_result == null || _result!.isError) return;
    final isConnected = widget.ref.read(bleProvider).connection == BleConnectionState.connected;
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스피커를 먼저 연결하세요')));
      return;
    }
    setState(() => _applying = true);
    final enabledBands = _result!.bands.where((b) => b['enabled'] != false).toList();
    final peaks = enabledBands.map((b) => ResonancePeak(
      frequency: (b['frequency'] as num).toDouble(),
      gain: (b['gainDb'] as num).toDouble(),
      q: (b['q'] as num).toDouble(),
    )).toList();
    final packets = DspCompiler.compileAll(peaks);
    await widget.ref.read(bleProvider.notifier).sendPackets(packets);
    setState(() => _applying = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('AI 추천 ${peaks.length}개 밴드 DSP 적용 완료'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.ref.watch(bleProvider).connection == BleConnectionState.connected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: const InputDecoration(
          labelText: 'AI에게 요청',
          labelStyle: TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
        ),
      ),
      const SizedBox(height: 12),
      _OutlineButton(
        label: _loading ? 'AI 분석 중...' : 'AI 튜닝 요청',
        loading: _loading,
        enabled: widget.mState.peaks.isNotEmpty,
        onTap: widget.mState.peaks.isEmpty ? null : _suggest,
      ),
      if (_result != null && !_result!.isError) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6)),
          child: Text(_result!.explanation, style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.6)),
        ),
        const SizedBox(height: 12),
        ..._result!.bands.asMap().entries.map((e) {
          final idx = e.key;
          final b = e.value;
          final active = b['enabled'] != false;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 4, height: 4, margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(color: active ? Colors.white38 : Colors.white12, shape: BoxShape.circle)),
              Expanded(child: Text('${b['frequency']}Hz', style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 13))),
              Text('${b['gainDb']}dB', style: TextStyle(color: active ? Colors.white60 : Colors.white24, fontSize: 12)),
              const SizedBox(width: 12),
              Text('Q${b['q']}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              const SizedBox(width: 12),
              if (active && isConnected)
                GestureDetector(
                  onTap: () => _applyBand(b, idx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(3)),
                    child: const Text('APPLY', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
                  ),
                ),
            ]),
          );
        }),
        const SizedBox(height: 12),
        _OutlineButton(
          label: _applying ? 'SENDING...' : 'APPLY ALL',
          loading: _applying,
          enabled: isConnected && !_applying,
          onTap: isConnected ? _applyAll : null,
        ),
        if (!isConnected)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('스피커 연결 후 적용 가능합니다', style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
          ),
      ],
      if (_result != null && _result!.isError)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_result!.explanation, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
        ),
    ]);
  }
}
