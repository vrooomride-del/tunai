import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../../core/ai_tuning_service.dart';
import '../../core/audio_analyzer.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/speaker_profile.dart';
import '../../core/install_location.dart';
import '../dsp/dsp_compiler.dart';
import '../../shared/widgets.dart';

/// AI 탭 — 측정 결과를 AI가 분석해 PEQ를 제안하고, 이유를 설명하고, APPLY 한다.
/// "DSP를 조작하는 화면"이 아니라 "AI가 만든 결과를 확인하는 화면".
class AiScreen extends ConsumerWidget {
  final VoidCallback onApplied;
  const AiScreen({super.key, required this.onApplied});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'AI'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: mState.peaks.isEmpty
                    ? const _EmptyState()
                    : _AiTunePanel(mState: mState, onApplied: onApplied),
              ),
            ),
          ],
        ),
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
        Icon(Icons.auto_awesome_outlined, color: Colors.white24, size: 32),
        SizedBox(height: 10),
        Text('아직 측정 데이터가 없습니다', style: TextStyle(color: Colors.white54, fontSize: 13)),
        SizedBox(height: 4),
        Text('MEASURE 탭에서 먼저 측정을 진행하세요', style: TextStyle(color: Colors.white24, fontSize: 11)),
      ]),
    );
  }
}

class _AiTunePanel extends ConsumerStatefulWidget {
  final MeasurementState mState;
  final VoidCallback onApplied;
  const _AiTunePanel({required this.mState, required this.onApplied});
  @override
  ConsumerState<_AiTunePanel> createState() => _AiTunePanelState();
}

class _AiTunePanelState extends ConsumerState<_AiTunePanel> {
  bool _loading = false;
  bool _applying = false;
  AiTuningResult? _result;
  final _ctrl = TextEditingController(text: '자연스럽고 균형잡힌 소리로 튜닝해줘');
  SystemProfileId? _lastProfileId;
  bool _autoRequested = false;

  @override
  void didUpdateWidget(_AiTunePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mState.peaks.isEmpty && widget.mState.peaks.isNotEmpty && !_loading && _result == null) {
      _suggest();
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.mState.peaks.isNotEmpty && !_autoRequested) {
      _autoRequested = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _suggest());
    }
  }

  Future<void> _editBandHz(int idx, num current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Band ${idx + 1} — 주파수', style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(suffixText: 'Hz', suffixStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () { final v = double.tryParse(ctrl.text); if (v != null) Navigator.pop(ctx, v.clamp(20, 20000)); }, child: const Text('확인', style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (v != null) setState(() => _result!.bands[idx]['frequency'] = v);
  }

  Future<void> _editBandDb(int idx, num current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(1));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Band ${idx + 1} — 게인', style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(suffixText: 'dB', suffixStyle: TextStyle(color: Colors.white54),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () { final v = double.tryParse(ctrl.text); if (v != null) Navigator.pop(ctx, v.clamp(-24, 24)); }, child: const Text('확인', style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (v != null) setState(() => _result!.bands[idx]['gainDb'] = v);
  }

  Future<void> _editBandQ(int idx, num current) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(2));
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('Band ${idx + 1} — Q', style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(controller: ctrl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(onPressed: () { final v = double.tryParse(ctrl.text); if (v != null) Navigator.pop(ctx, v.clamp(0.1, 16)); }, child: const Text('확인', style: TextStyle(color: Colors.white70))),
        ],
      ),
    );
    if (v != null) setState(() => _result!.bands[idx]['q'] = v);
  }

  Future<void> _suggest() async {
    setState(() { _loading = true; _result = null; });
    final location = ref.read(installLocationProvider);
    final result = await AiTuningService.suggest(
      peaks: widget.mState.peaks,
      userRequest: _ctrl.text,
      speakerProfile: ref.read(speakerProfileProvider),
      location: location?.promptKey,
    );
    if (mounted) setState(() { _loading = false; _result = result; });
  }

  Future<void> _applyAll() async {
    if (_result == null || _result!.isError) return;
    final isConnected = ref.read(bleProvider).connection == BleConnectionState.connected;
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('스피커를 먼저 연결하세요')));
      return;
    }
    setState(() => _applying = true);
    final maxBands = ref.read(systemProfileProvider).maxPeqBands;
    final enabledBands = _result!.bands
        .take(maxBands)
        .where((b) => b['enabled'] != false)
        .toList();
    final peaks = enabledBands.map((b) => ResonancePeak(
      frequency: (b['frequency'] as num).toDouble(),
      gain: (b['gainDb'] as num).toDouble(),
      q: (b['q'] as num).toDouble(),
    )).toList();
    final packets = DspCompiler.compileAll(peaks);
    final ok = await ref.read(bleProvider.notifier).sendPackets(packets);
    if (mounted) setState(() => _applying = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('AI 추천 ${peaks.length}개 밴드 APPLY 완료'),
    ));
    if (ok) widget.onApplied();
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = ref.watch(bleProvider).connection == BleConnectionState.connected;
    final profile = ref.watch(systemProfileProvider);
    final maxBands = profile.maxPeqBands;
    if (_lastProfileId != null && _lastProfileId != profile.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _result = null; _loading = false; });
      });
    }
    _lastProfileId = profile.id;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'AI에게 요청',
          labelStyle: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6, runSpacing: 6,
        children: ['저음 강조', '고음 감소', '보컬 선명', '전체 플랫', '자동 균형']
            .map((q) => GestureDetector(
              onTap: () { _ctrl.text = q; },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(20)),
                child: Text(q, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            )).toList(),
      ),
      const SizedBox(height: 12),
      OutlineButton(
        label: _loading ? 'AI 분석 중...' : 'AI 튜닝 요청',
        loading: _loading,
        enabled: widget.mState.peaks.isNotEmpty,
        onTap: widget.mState.peaks.isEmpty ? null : _suggest,
      ),
      if (_result != null && !_result!.isError) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(6),
            color: Colors.amber.withValues(alpha: 0.04),
          ),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('⚠️ ', style: TextStyle(fontSize: 12)),
            Expanded(child: Text(
              'PEQ 값 조정 시 트위터 채널 게인을 크게 올리지 마세요. '
              '볼륨이 높은 상태에서 트위터가 손상될 수 있습니다.',
              style: TextStyle(color: Colors.amber, fontSize: 12, height: 1.5),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6)),
          child: Text(_result!.explanation, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.7)),
        ),
        const SizedBox(height: 12),
        ..._result!.bands.take(maxBands).toList().asMap().entries.map((e) {
          final idx = e.key;
          final b = e.value;
          final active = b['enabled'] != false;
          final hz = b['frequency'] as num;
          final db = b['gainDb'] as num;
          final q  = b['q'] as num;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: active ? Colors.white24 : Colors.white12),
                borderRadius: BorderRadius.circular(6),
                color: active ? Colors.white.withValues(alpha: 0.02) : Colors.transparent,
              ),
              child: Row(children: [
                SizedBox(
                  width: 24,
                  child: Text('${idx + 1}',
                      style: TextStyle(color: active ? Colors.white38 : Colors.white12,
                          fontSize: 11, fontFamily: 'monospace')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => _editBandHz(idx, hz),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${hz.toStringAsFixed(0)} Hz',
                          style: TextStyle(color: active ? Colors.white : Colors.white38,
                              fontSize: 16, fontWeight: FontWeight.w500)),
                      const Text('FREQ', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                    ]),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _editBandDb(idx, db),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB',
                          style: TextStyle(
                              color: active ? (db >= 0 ? Colors.white : Colors.white70) : Colors.white38,
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      const Text('GAIN', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                    ]),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _editBandQ(idx, q),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Q ${q.toStringAsFixed(2)}',
                          style: TextStyle(color: active ? Colors.white70 : Colors.white38, fontSize: 15)),
                      const Text('Q', style: TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
                    ]),
                  ),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 12),
        OutlineButton(
          label: _applying ? 'SENDING...' : 'APPLY',
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
