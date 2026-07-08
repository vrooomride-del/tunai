import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../measurement/measurement_controller.dart';
import '../ble/ble_controller.dart';
import '../../core/ai_tuning_service.dart';
import '../../core/audio_analyzer.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/sound_score_calculator.dart';
import '../../core/speaker_profile.dart';
import '../../core/install_location.dart';
import '../../core/spectrum_snapshot.dart';
import '../dsp/dsp_compiler.dart';
import '../../shared/spectrum_chart.dart';
import '../../core/first_run_state.dart';
import '../../core/sound_profile_store.dart';
import '../../shared/acoustic_result_card.dart';

/// AI 탭 — 측정 결과를 AI가 분석해 PEQ를 제안하고, 이유를 설명하고, APPLY 한다.
class AiScreen extends ConsumerWidget {
  final VoidCallback onApplied;
  final void Function(int)? onGoTo;
  const AiScreen({super.key, required this.onApplied, this.onGoTo});

  bool _isKo(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'ko';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    final ko = _isKo(context);

    if (mState.peaks.isEmpty) {
      return _AiEmptyState(ko: ko, onGoToRoom: onGoTo != null ? () => onGoTo!(1) : null);
    }

    return _AiTunePanel(mState: mState, onApplied: onApplied, ko: ko);
  }
}

class _AiEmptyState extends StatelessWidget {
  final bool ko;
  final VoidCallback? onGoToRoom;
  const _AiEmptyState({required this.ko, this.onGoToRoom});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(flex: 2),
              Text(
                ko ? '아직 공간 프로파일이 없습니다.' : 'No room profile yet.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w300,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                ko
                    ? '먼저 공간 스캔을 완료하면\n어쿠스틱 튠을 만들 수 있습니다.'
                    : 'Run a Room Scan first to create\nyour Acoustic Tune.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 14,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 36),
              if (onGoToRoom != null)
                GestureDetector(
                  onTap: onGoToRoom,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      ko ? '공간 스캔 시작' : 'Start Room Scan',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiTunePanel extends ConsumerStatefulWidget {
  final MeasurementState mState;
  final VoidCallback onApplied;
  final bool ko;
  const _AiTunePanel({required this.mState, required this.onApplied, required this.ko});
  @override
  ConsumerState<_AiTunePanel> createState() => _AiTunePanelState();
}

class _AiTunePanelState extends ConsumerState<_AiTunePanel> {
  bool _loading = false;
  bool _applying = false;
  AiTuningResult? _result;
  int? _previousScore;
  final _ctrl = TextEditingController(text: '자연스럽고 균형잡힌 소리로 튜닝해줘');
  SystemProfileId? _lastProfileId;
  bool _autoRequested = false;
  String? _savedProfileId;  // 저장 완료된 profile id (null = 미저장)
  String _selectedRef = 'Neutral';

  static const _refPresets = ['Warm', 'Neutral', 'Clear'];

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
    final previousScore = _result?.soundScore;
    setState(() { _loading = true; _result = null; });
    final location = ref.read(installLocationProvider);
    final refHint = _selectedRef != 'Neutral' ? ' Reference: $_selectedRef.' : '';
    final spectrum = ref.read(spectrumSnapshotProvider).before;
    final score = ref.read(soundScoreProvider);
    final result = await AiTuningService.suggest(
      peaks: widget.mState.peaks,
      userRequest: _ctrl.text + refHint,
      speakerProfile: ref.read(speakerProfileProvider),
      location: location?.promptKey,
      spectrum: spectrum,
      soundScore: score,
    );
    if (mounted) setState(() { _loading = false; _result = result; _previousScore = previousScore; });
    if (!result.isError) ref.read(lastAiResultProvider.notifier).state = result;
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
    if (ok) {
      ref.read(spectrumSnapshotProvider.notifier).applyPeaks(peaks);
      ref.read(acousticTuneAppliedProvider.notifier).state = true;
      // 저장된 프로파일이 있으면 Applied 상태 업데이트
      if (_savedProfileId != null) {
        ref.read(soundProfileStoreProvider.notifier).markApplied(_savedProfileId!);
      }
      widget.onApplied();
    }
  }

  Future<void> _saveProfile(String name) async {
    if (_result == null) return;
    final loc = ref.read(installLocationProvider);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final profile = UiSoundProfile(
      id: id,
      name: name,
      roomTypeLabel: loc?.label ?? '공간',
      roomTypeLabelEn: loc?.labelEn ?? 'Room',
      soundScore: _result!.soundScore,
      createdAt: DateTime.now(),
      isApplied: false,
      bands: List<Map<String, dynamic>>.from(_result!.bands),
      summary: _result!.explanation.isNotEmpty ? _result!.explanation : null,
    );
    await ref.read(soundProfileStoreProvider.notifier).add(profile);
    if (mounted) setState(() => _savedProfileId = id);
  }

  @override
  Widget build(BuildContext context) {
    final ko = widget.ko;
    final isConnected = ref.watch(bleProvider).connection == BleConnectionState.connected;
    final profile = ref.watch(systemProfileProvider);
    final maxBands = profile.maxPeqBands;
    if (_lastProfileId != null && _lastProfileId != profile.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() { _result = null; _loading = false; _previousScore = null; });
      });
    }
    _lastProfileId = profile.id;

    // ── AI 로딩 중 ──────────────────────────────────────────────────────────
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ko ? '공간의 소리를 이해하고 있습니다...' : 'TUNAI is understanding your room...',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.w300, height: 1.4),
                ),
                const Spacer(),
                const LinearProgressIndicator(
                  backgroundColor: Colors.white12,
                  color: Colors.white38,
                  minHeight: 1.5,
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      );
    }

    // ── AI 완료 후 최적화 완료 화면 (Screen 9) ───────────────────────────────
    if (_result != null && !_result!.isError) {
      return _OptimizedView(
        ko: ko,
        result: _result!,
        previousScore: _previousScore,
        isConnected: isConnected,
        applying: _applying,
        maxBands: maxBands,
        onApply: _applyAll,
        onSave: _saveProfile,
        savedProfileId: _savedProfileId,
        onRerun: _suggest,
        onEditHz: _editBandHz,
        onEditDb: _editBandDb,
        onEditQ: _editBandQ,
        snap: ref.watch(spectrumSnapshotProvider),
        installLocation: ref.watch(installLocationProvider),
      );
    }

    // ── 에러 ─────────────────────────────────────────────────────────────────
    if (_result != null && _result!.isError) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(32, 60, 32, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ko ? 'AI 오류' : 'AI Error',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 12, letterSpacing: 2),
                ),
                const SizedBox(height: 16),
                Text(
                  _result!.explanation,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14, height: 1.5),
                ),
                const Spacer(),
                _AiBigButton(label: ko ? '다시 시도' : 'Try Again', onTap: _suggest),
              ],
            ),
          ),
        ),
      );
    }

    // ── AI 요청 전 기본 화면 ─────────────────────────────────────────────────
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ko ? '공간에 맞는 어쿠스틱 튠을\n만들 준비가 됐습니다.' : 'Ready to create your Acoustic Tune\nfor this room.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _ComputedScoreRow(),
                    const SizedBox(height: 32),
                    // 요청 입력
                    TextField(
                      controller: _ctrl,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: ko ? 'AI에게 요청 (선택)' : 'Request to AI (optional)',
                        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                        enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white12)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: (ko
                          ? ['저음 강조', '고음 감소', '보컬 선명', '전체 플랫', '자동 균형']
                          : ['Warm bass', 'Less treble', 'Clear vocals', 'Flat', 'Auto'])
                          .map((q) => GestureDetector(
                            onTap: () => setState(() => _ctrl.text = q),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white12),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(q, style: TextStyle(color: Colors.white.withValues(alpha: 0.38), fontSize: 11)),
                            ),
                          )).toList(),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: _refPresets.map((r) {
                        final active = r == _selectedRef;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: r == _refPresets.last ? 0 : 6),
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedRef = r),
                              child: Container(
                                height: 32,
                                decoration: BoxDecoration(
                                  color: active ? Colors.white : Colors.transparent,
                                  border: Border.all(color: active ? Colors.white : Colors.white24),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Center(
                                  child: Text(r.toUpperCase(),
                                      style: TextStyle(
                                          color: active ? Colors.black : Colors.white54,
                                          fontSize: 10, letterSpacing: 1.5,
                                          fontWeight: active ? FontWeight.w600 : FontWeight.w300)),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _AiBigButton(
                label: ko ? '어쿠스틱 튠 생성' : 'Create Acoustic Tune',
                onTap: _suggest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Screen 9: 최적화 완료 화면 ────────────────────────────────────────────────
class _OptimizedView extends StatelessWidget {
  final bool ko;
  final AiTuningResult result;
  final int? previousScore;
  final bool isConnected;
  final bool applying;
  final int maxBands;
  final VoidCallback onApply;
  final Future<void> Function(String name) onSave;
  final String? savedProfileId;
  final VoidCallback onRerun;
  final Function(int, num) onEditHz;
  final Function(int, num) onEditDb;
  final Function(int, num) onEditQ;
  final SpectrumSnapshot snap;
  final InstallLocation? installLocation;

  const _OptimizedView({
    required this.ko,
    required this.result,
    required this.previousScore,
    required this.isConnected,
    required this.applying,
    required this.maxBands,
    required this.onApply,
    required this.onSave,
    required this.savedProfileId,
    required this.onRerun,
    required this.onEditHz,
    required this.onEditDb,
    required this.onEditQ,
    required this.snap,
    required this.installLocation,
  });

  @override
  Widget build(BuildContext context) {
    final score = result.soundScore;
    final prev = previousScore;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 상태 레이블
                    Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF69F0AE),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        ko ? 'Room Matched' : 'Room Matched',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.45),
                          fontSize: 11,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // 타이틀
                    Text(
                      ko
                          ? '이 공간에 맞는 소리로\n조정되었습니다.'
                          : 'Your sound is now matched\nto this room.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w300,
                        height: 1.35,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      ko
                          ? '공간에서 생긴 저역 부밍을 줄이고, 보컬 명료도와 스테레오 밸런스를 개선했습니다.'
                          : 'TUNAI reduced room boom, improved vocal clarity, and balanced the stereo image.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 14,
                        height: 1.65,
                      ),
                    ),

                    // Sound Score 변화
                    if (score != null) ...[
                      const SizedBox(height: 28),
                      _ScoreDelta(score: score, previous: prev, ko: ko),
                    ],

                    // 설명 텍스트
                    if (result.explanation.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        result.explanation,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 13,
                          height: 1.7,
                        ),
                      ),
                    ],

                    // ── Acoustic Result Cards ──────────────────────────
                    const SizedBox(height: 32),
                    Text(
                      ko ? 'TUNAI가 발견한 것' : 'What TUNAI found',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._buildAcousticCards(ko),

                    // ── Score Breakdown ────────────────────────────────
                    if (score != null) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                ko
                                    ? 'Sound Score는 공간 맞춤 정도, 밸런스, 명료도를 종합한 점수입니다.'
                                    : 'Sound Score reflects room matching, balance, and clarity after tuning.',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.28),
                                  fontSize: 10,
                                  height: 1.5,
                                ),
                              ),
                            ),
                            const Divider(color: Colors.white12, height: 12),
                            ScoreBreakdownRow(label: ko ? '공간 맞춤' : 'Room Match', value: ko ? '우수' : 'Excellent', ko: ko),
                            ScoreBreakdownRow(label: ko ? '저역 제어' : 'Bass Control', value: ko ? '개선됨' : 'Improved', ko: ko),
                            ScoreBreakdownRow(label: ko ? '보컬 명료도' : 'Vocal Clarity', value: ko ? '개선됨' : 'Improved', ko: ko),
                            ScoreBreakdownRow(label: ko ? '스테레오 밸런스' : 'Stereo Balance', value: ko ? '중앙 정렬' : 'Centered', ko: ko),
                          ],
                        ),
                      ),
                    ],

                    // 밴드 목록 (축약형)
                    const SizedBox(height: 20),
                    ..._buildBandList(context),
                  ],
                ),
              ),
            ),

            // 하단 버튼들
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
              child: Row(children: [
                Expanded(
                  child: _AiBigButton(
                    label: ko ? 'Hear Before / After 듣기' : 'Hear Before / After',
                    filled: false,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => _BeforeAfterView(ko: ko, snap: snap),
                    )),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: _AiBigButton(
                label: applying
                    ? (ko ? '적용 중...' : 'Applying...')
                    : (ko ? '사운드 프로파일 적용' : 'Apply Sound Profile'),
                onTap: applying || !isConnected ? null : onApply,
              ),
            ),
            if (!isConnected)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Center(
                  child: Text(
                    ko
                        ? '이 사운드 프로파일을 적용하려면 TUNAI 스피커를 연결해주세요.'
                        : 'Connect your TUNAI speaker to apply this Sound Profile.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 11),
                  ),
                ),
              ),
            // Save Sound Profile 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 4, 32, 28),
              child: savedProfileId != null
                  ? Center(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.check_circle_outline, color: Colors.white.withValues(alpha: 0.4), size: 14),
                        const SizedBox(width: 6),
                        Text(
                          ko ? '사운드 프로파일이 저장되었습니다.' : 'Sound Profile saved.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                        ),
                      ]),
                    )
                  : GestureDetector(
                      onTap: () => _showSaveDialog(context),
                      child: Center(
                        child: Text(
                          ko ? '사운드 프로파일 저장' : 'Save Sound Profile',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 13,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _defaultProfileName(bool ko) {
    if (installLocation == null) return ko ? '나의 어쿠스틱 튠' : 'My Acoustic Tune';
    if (ko) {
      return switch (installLocation!) {
        InstallLocation.desk        => '책상 위 어쿠스틱 튠',
        InstallLocation.livingRoom  => '거실 어쿠스틱 튠',
        InstallLocation.nearWall    => '벽 가까이 어쿠스틱 튠',
        InstallLocation.studio      => '스튜디오 어쿠스틱 튠',
        InstallLocation.custom      => '나의 어쿠스틱 튠',
      };
    } else {
      return switch (installLocation!) {
        InstallLocation.desk        => 'Desk Acoustic Tune',
        InstallLocation.livingRoom  => 'Living Room Acoustic Tune',
        InstallLocation.nearWall    => 'Near Wall Acoustic Tune',
        InstallLocation.studio      => 'Studio Acoustic Tune',
        InstallLocation.custom      => 'My Acoustic Tune',
      };
    }
  }

  Future<void> _showSaveDialog(BuildContext context) async {
    final ctrl = TextEditingController(text: _defaultProfileName(ko));
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          ko ? '사운드 프로파일 이름 지정' : 'Name your Sound Profile',
          style: const TextStyle(color: Colors.white, fontSize: 15),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white, fontSize: 14),
          decoration: const InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white70)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ko ? '취소' : 'Cancel', style: const TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isNotEmpty) Navigator.pop(ctx, n);
            },
            child: Text(ko ? '저장' : 'Save', style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await onSave(name);
    }
  }

  List<Widget> _buildAcousticCards(bool ko) {
    // 실제 분석 데이터(peaks)가 있으면 우선 사용, 없으면 기본 3장 표시
    final peaks = result.bands
        .where((b) => b['enabled'] != false && (b['reason'] as String? ?? '').isNotEmpty)
        .take(3)
        .toList();

    if (peaks.isNotEmpty) {
      return peaks.map((b) {
        final hz = (b['frequency'] as num).toStringAsFixed(0);
        final db = b['gainDb'] as num;
        final reason = b['reason'] as String? ?? '';
        return AcousticResultCard(
          title: ko ? _koTitle(hz) : _enTitle(hz),
          frequencyLabel: '${hz}Hz',
          cause: reason,
          correction: ko
              ? '${db < 0 ? '과도한' : '부족한'} ${hz}Hz 대역을 ${db.abs().toStringAsFixed(1)}dB 조정했습니다.'
              : '${db < 0 ? 'Reduced' : 'Boosted'} ${hz}Hz by ${db.abs().toStringAsFixed(1)}dB.',
          effect: ko ? '해당 대역의 소리가 더 자연스럽게 들립니다.' : 'That frequency range now sounds more natural.',
          ko: ko,
        );
      }).toList();
    }

    // fallback 기본 카드 3장
    return [
      AcousticResultCard(
        title: ko ? '저역 부밍' : 'Bass Buildup',
        frequencyLabel: ko ? '90Hz 부근' : 'Around 90Hz',
        cause: ko
            ? '스피커가 벽이나 경계면 가까이에 있어 저역이 강조되었습니다.'
            : 'Your speaker is close to a wall or boundary.',
        correction: ko
            ? '과도한 저역 에너지를 줄였습니다.'
            : 'TUNAI reduced excessive low-frequency energy.',
        effect: ko
            ? '저음이 더 단단하고 덜 울리게 들립니다.'
            : 'Bass should sound tighter and less boomy.',
        ko: ko,
      ),
      AcousticResultCard(
        title: ko ? '책상 반사' : 'Desk Reflection',
        frequencyLabel: ko ? '180Hz 부근' : 'Around 180Hz',
        cause: ko
            ? '책상에서 생긴 초기 반사가 보컬을 두껍게 만들 수 있습니다.'
            : 'Early reflections from the desk can make vocals sound thick.',
        correction: ko
            ? '영향을 받은 대역을 자연스럽게 정리했습니다.'
            : 'TUNAI softened the affected range.',
        effect: ko
            ? '보컬이 더 또렷하고 자연스럽게 들립니다.'
            : 'Vocals should sound clearer and more natural.',
        ko: ko,
      ),
      AcousticResultCard(
        title: ko ? '스테레오 밸런스' : 'Stereo Balance',
        frequencyLabel: ko ? '좌 / 우' : 'Left / Right',
        cause: ko
            ? '청취 위치나 공간 구조 때문에 음상이 한쪽으로 치우칠 수 있습니다.'
            : 'The listening position or room layout can shift the stereo image.',
        correction: ko
            ? '더 중앙에 맺히도록 밸런스를 조정했습니다.'
            : 'TUNAI adjusted the balance for a more centered image.',
        effect: ko
            ? '음상이 더 안정적이고 중앙에 맺히는 느낌을 줍니다.'
            : 'The sound image should feel more stable and centered.',
        ko: ko,
      ),
    ];
  }

  String _enTitle(String hz) {
    final f = double.tryParse(hz) ?? 0;
    if (f < 150) return 'Bass Buildup';
    if (f < 400) return 'Desk Reflection';
    if (f < 1000) return 'Room Resonance';
    return 'High-Frequency Detail';
  }

  String _koTitle(String hz) {
    final f = double.tryParse(hz) ?? 0;
    if (f < 150) return '저역 부밍';
    if (f < 400) return '공간 반사';
    if (f < 1000) return '공간 공진';
    return '고역 디테일';
  }

  List<Widget> _buildBandList(BuildContext context) {
    final bands = result.bands.take(maxBands).toList();
    if (bands.isEmpty) return [];
    return [
      Text(
        ko ? 'EQ 조정 내역 (탭하여 수정)' : 'EQ adjustments (tap to edit)',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 11,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 10),
      ...bands.asMap().entries.map((e) {
        final idx = e.key;
        final b = e.value;
        final active = b['enabled'] != false;
        final hz = b['frequency'] as num;
        final db = b['gainDb'] as num;
        final q  = b['q'] as num;
        final reason = b['reason'] as String?;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => onEditHz(idx, hz),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: active ? Colors.white12 : Colors.white.withValues(alpha: 0.05)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Expanded(
                  flex: 3,
                  child: Text('${hz.toStringAsFixed(0)} Hz',
                      style: TextStyle(
                          color: active ? Colors.white : Colors.white38,
                          fontSize: 14, fontWeight: FontWeight.w400)),
                ),
                GestureDetector(
                  onTap: () => onEditDb(idx, db),
                  child: Text('${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB',
                      style: TextStyle(
                          color: active
                              ? (db.abs() > 3
                                  ? const Color(0xFFFF5252)
                                  : Colors.white70)
                              : Colors.white24,
                          fontSize: 14)),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () => onEditQ(idx, q),
                  child: Text('Q ${q.toStringAsFixed(1)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3), fontSize: 12)),
                ),
                if (reason != null && reason.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Text(reason,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.25),
                            fontSize: 10,
                            fontStyle: FontStyle.italic),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ]),
            ),
          ),
        );
      }),
    ];
  }
}

// ── Score 변화 표시 ───────────────────────────────────────────────────────────
class _ScoreDelta extends StatelessWidget {
  final int score;
  final int? previous;
  final bool ko;
  const _ScoreDelta({required this.score, this.previous, required this.ko});

  @override
  Widget build(BuildContext context) {
    final delta = previous != null ? score - previous! : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        Text(
          ko ? 'Sound Score' : 'Sound Score',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, letterSpacing: 1.5),
        ),
        const Spacer(),
        if (previous != null) ...[
          Text('$previous',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 22, fontWeight: FontWeight.w300)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('→',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 18)),
          ),
        ],
        Text('$score',
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300)),
        if (delta != null) ...[
          const SizedBox(width: 8),
          Text('${delta >= 0 ? '+' : ''}$delta',
              style: TextStyle(
                  color: delta >= 0
                      ? const Color(0xFF69F0AE)
                      : const Color(0xFFFF5252),
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ]),
    );
  }
}

// ── Screen 10: Before / After 화면 ───────────────────────────────────────────
class _BeforeAfterView extends StatefulWidget {
  final bool ko;
  final SpectrumSnapshot snap;
  const _BeforeAfterView({required this.ko, required this.snap});
  @override
  State<_BeforeAfterView> createState() => _BeforeAfterViewState();
}

class _BeforeAfterViewState extends State<_BeforeAfterView> {
  bool _showOriginal = true;

  @override
  Widget build(BuildContext context) {
    final ko = widget.ko;
    final snap = widget.snap;
    final bins = _showOriginal ? snap.before : (snap.afterAi ?? snap.before);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 뒤로가기
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text(
                  ko ? '← 뒤로' : '← Back',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              Text(
                ko ? '차이를 들어보세요.' : 'Hear the difference.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w300,
                  height: 1.3,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                ko
                    ? '원래 소리와 어쿠스틱 튠을 즉시 비교해보세요.'
                    : 'Switch instantly between the original sound and the optimized sound.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.45),
                  fontSize: 14,
                  height: 1.65,
                ),
              ),

              const Spacer(flex: 2),

              // 토글
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showOriginal = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _showOriginal ? Colors.white : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(5)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          ko ? '원래 소리' : 'Original Sound',
                          style: TextStyle(
                            color: _showOriginal ? Colors.black : Colors.white.withValues(alpha: 0.4),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showOriginal = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: !_showOriginal ? Colors.white : Colors.transparent,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          ko ? '어쿠스틱 튠' : 'Acoustic Tune',
                          style: TextStyle(
                            color: !_showOriginal ? Colors.black : Colors.white.withValues(alpha: 0.4),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 24),

              // 스펙트럼 차트
              if (bins != null && bins.isNotEmpty) ...[
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: SizedBox(
                    key: ValueKey(_showOriginal),
                    height: 200,
                    child: SpectrumChart(bins: bins, peaks: const []),
                  ),
                ),
              ] else ...[
                Container(
                  height: 80,
                  alignment: Alignment.center,
                  child: Text(
                    ko
                        ? '아직 비교할 공간 프로파일이 없습니다.\n먼저 공간 스캔을 완료하면 원래 소리와 어쿠스틱 튠을 비교할 수 있습니다.'
                        : 'No room profile yet.\nRun a Room Scan first to compare Original Sound and Acoustic Tune.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // 상태 설명 카드
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: _showOriginal
                    ? SoundStateCard(
                        key: const ValueKey('original'),
                        title: ko ? '원래 소리' : 'Original Sound',
                        subtitle: ko
                            ? '공간의 영향이 그대로 포함된 소리입니다.'
                            : 'Room effect included. No correction applied.',
                        selected: true,
                      )
                    : SoundStateCard(
                        key: const ValueKey('tune'),
                        title: ko ? '어쿠스틱 튠' : 'Acoustic Tune',
                        subtitle: ko
                            ? '저역 부밍을 줄이고, 보컬 명료도와 스테레오 밸런스를 개선한 소리입니다.'
                            : 'Room boom reduced. Vocal clarity and stereo balance improved.',
                        selected: true,
                      ),
              ),

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 공용 버튼 ─────────────────────────────────────────────────────────────────
class _AiBigButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _AiBigButton({required this.label, this.onTap, this.filled = true});
  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: filled && enabled ? Colors.white : Colors.transparent,
          border: !(filled && enabled) ? Border.all(color: Colors.white24) : null,
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: filled && enabled ? Colors.black : Colors.white.withValues(alpha: 0.45),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}


/// 측정 스펙트럼 기반 클라이언트 측 Sound Score 미리보기 (AI 결과 전 표시)
class _ComputedScoreRow extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final score = ref.watch(soundScoreProvider);
    if (score == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(children: [
        const Icon(Icons.analytics_outlined, color: Colors.white38, size: 14),
        const SizedBox(width: 8),
        Text('측정 Score: ${score.total}/100',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(score.explanation,
              style: const TextStyle(color: Colors.white24, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
