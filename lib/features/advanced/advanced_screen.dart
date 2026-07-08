import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../ble/ble_controller.dart';
import '../../core/profiles/system_profile.dart';
import '../../core/speaker_profile.dart';
import '../../core/frd_parser.dart';
import '../../core/channel_link_provider.dart';
import '../../core/dsp/dsp_adapter.dart';
import '../../shared/widgets.dart';
import '../history/history_screen.dart';
import '../device/device_screen.dart';

class AdvancedScreen extends ConsumerWidget {
  const AdvancedScreen({super.key});

  void _showProDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('TUNAI PRO', style: TextStyle(color: Colors.white, fontSize: 15, letterSpacing: 2)),
        content: const Text(
          'Full PEQ, crossover, and driver controls are available in TUNAI PRO.\n\nComing Soon.',
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bState = ref.watch(bleProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'ADVANCED'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Speaker Profile ──────────────────────────────────
                    const _SectionLabel('SPEAKER PROFILE'),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('TUNAI ONE',
                            style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text('5.25" 동축 2웨이 액티브 스피커',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45), fontSize: 12)),
                      ]),
                    ),
                    const SizedBox(height: 20),

                    // ── Board / System Profile ───────────────────────────
                    const _SectionLabel('보드 · 시스템 프로파일'),
                    const SizedBox(height: 8),
                    const SectionCard(child: _SpeakerSelectPanel()),
                    Consumer(builder: (_, r, __) {
                      final sys = r.watch(systemProfileProvider);
                      final sp = r.watch(speakerProfileProvider);
                      if (sys.crossoverPoints < 1 || sp == null) return const SizedBox.shrink();
                      return Column(children: [
                        const SizedBox(height: 20),
                        const _SectionLabel('크로스오버 · 채널 게인'),
                        const SizedBox(height: 8),
                        _CrossoverCard(profile: sp, bState: bState),
                      ]);
                    }),
                    const SizedBox(height: 20),
                    const _SectionLabel('내 스피커 · 기록'),
                    const SizedBox(height: 8),
                    _MenuRow(label: '내 스피커 등록 (QR)', icon: Icons.qr_code_scanner,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DeviceScreen()))),
                    const SizedBox(height: 8),
                    _MenuRow(label: 'HISTORY (내 측정 기록)', icon: Icons.history,
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HistoryScreen()))),
                    const SizedBox(height: 28),

                    // ── TUNAI PRO ────────────────────────────────────────
                    GestureDetector(
                      onTap: () => _showProDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white24),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Text(
                          'Open in TUNAI PRO',
                          style: TextStyle(color: Colors.white54, fontSize: 13, letterSpacing: 1.5),
                        ),
                      ),
                    ),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 2));
}

class _MenuRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _MenuRow({required this.label, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Icon(icon, color: Colors.white38, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, letterSpacing: 1))),
          const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
        ]),
      ),
    );
  }
}

class _SpeakerSelectPanel extends ConsumerStatefulWidget {
  const _SpeakerSelectPanel();
  @override
  ConsumerState<_SpeakerSelectPanel> createState() => _SpeakerSelectPanelState();
}

class _SpeakerSelectPanelState extends ConsumerState<_SpeakerSelectPanel> {
  String? _wooferFrdName;
  String? _tweeterFrdName;
  String? _frdError;

  bool _showTsInput = false;
  final _fsCtrl   = TextEditingController();
  final _qtsCtrl  = TextEditingController();
  final _vasCtrl  = TextEditingController();
  final _xmaxCtrl = TextEditingController();
  final _sensCtrl = TextEditingController();
  String? _tsError;

  @override
  void dispose() {
    _fsCtrl.dispose(); _qtsCtrl.dispose(); _vasCtrl.dispose();
    _xmaxCtrl.dispose(); _sensCtrl.dispose();
    super.dispose();
  }

  void _saveTs() {
    final fs   = double.tryParse(_fsCtrl.text);
    final qts  = double.tryParse(_qtsCtrl.text);
    final vas  = double.tryParse(_vasCtrl.text);
    final xmax = double.tryParse(_xmaxCtrl.text);
    final sens = double.tryParse(_sensCtrl.text);

    if (fs == null || qts == null) {
      setState(() => _tsError = 'Fs와 Qts는 필수입니다');
      return;
    }
    setState(() => _tsError = null);

    ref.read(speakerProfileProvider.notifier).state = SpeakerProfile(
      id: 'custom_ts',
      name: 'Custom T/S',
      description: 'Fs ${fs.toStringAsFixed(0)}Hz · Qts ${qts.toStringAsFixed(2)}',
      fs: fs,
      qts: qts,
      vas: vas ?? 5.0,
      xmax: xmax ?? 5.0,
      sensitivity: sens ?? 87.0,
    );
    setState(() => _showTsInput = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('T/S 파라미터 저장됨 — 크로스오버 ${(qts < 0.4 ? fs * 20 : qts < 0.7 ? fs * 28 : fs * 35).clamp(800, 6000).toStringAsFixed(0)}Hz 추천')),
    );
  }

  Future<void> _pickFrd({required bool isTweeter}) async {
    setState(() => _frdError = null);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['frd', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null) { setState(() => _frdError = '파일을 읽을 수 없습니다.'); return; }
      final content = String.fromCharCodes(bytes);
      final points = FrdParser.parseFrd(content);
      if (points.isEmpty) { setState(() => _frdError = '지원하지 않는 형식입니다. FRD 파일인지 확인하세요.'); return; }

      final current = ref.read(speakerProfileProvider);
      if (current == null) { setState(() => _frdError = '스피커 프로파일을 먼저 선택하세요.'); return; }

      final updated = SpeakerProfile(
        id: current.id, name: current.name, description: current.description,
        fs: current.fs, qts: current.qts, vas: current.vas,
        xmax: current.xmax, sensitivity: current.sensitivity,
        enclosureVolume: current.enclosureVolume,
        portLength: current.portLength, portDiameter: current.portDiameter,
        wooferFrd: isTweeter ? current.wooferFrd : points,
        tweeterFrd: isTweeter ? points : current.tweeterFrd,
      );
      ref.read(speakerProfileProvider.notifier).state = updated;
      setState(() {
        if (isTweeter) { _tweeterFrdName = file.name; }
        else { _wooferFrdName = file.name; }
      });
    } catch (e) {
      setState(() => _frdError = '파일 읽기 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(systemProfileProvider);
    final sp = ref.watch(speakerProfileProvider);
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
                      style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 14, letterSpacing: 1.5)),
                  const SizedBox(height: 2),
                  Text(profile.description,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(profile.chipLabel,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, letterSpacing: 1)),
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
        Text('${selected.channelCount}ch · 크로스오버 ${selected.crossoverPoints}개',
            style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),

        if (sp != null && selected.crossoverPoints >= 1) ...[
          const SizedBox(height: 14),
          const Divider(color: Colors.white12),
          const SizedBox(height: 10),
          const Text('FRD 파일 (선택)', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
          const SizedBox(height: 8),
          _FrdRow(
            label: '우퍼',
            fileName: _wooferFrdName,
            onTap: () => _pickFrd(isTweeter: false),
            onClear: _wooferFrdName == null ? null : () {
              ref.read(speakerProfileProvider.notifier).state = SpeakerProfile(
                id: sp.id, name: sp.name, description: sp.description,
                fs: sp.fs, qts: sp.qts, vas: sp.vas, xmax: sp.xmax, sensitivity: sp.sensitivity,
                enclosureVolume: sp.enclosureVolume, portLength: sp.portLength, portDiameter: sp.portDiameter,
                tweeterFrd: sp.tweeterFrd,
              );
              setState(() => _wooferFrdName = null);
            },
          ),
          const SizedBox(height: 6),
          _FrdRow(
            label: '트위터',
            fileName: _tweeterFrdName,
            onTap: () => _pickFrd(isTweeter: true),
            onClear: _tweeterFrdName == null ? null : () {
              ref.read(speakerProfileProvider.notifier).state = SpeakerProfile(
                id: sp.id, name: sp.name, description: sp.description,
                fs: sp.fs, qts: sp.qts, vas: sp.vas, xmax: sp.xmax, sensitivity: sp.sensitivity,
                enclosureVolume: sp.enclosureVolume, portLength: sp.portLength, portDiameter: sp.portDiameter,
                wooferFrd: sp.wooferFrd,
              );
              setState(() => _tweeterFrdName = null);
            },
          ),
          if (_frdError != null) ...[
            const SizedBox(height: 6),
            Text(_frdError!, style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
          ],
        ],

        const SizedBox(height: 14),
        const Divider(color: Colors.white12),
        const SizedBox(height: 10),
        const Text(
          'T/S 파라미터 (선택)',
          style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 2),
        ),
        const SizedBox(height: 4),
        const Text(
          'FRD/ZMA 파일 없어도 Fs·Qts만으로 크로스오버 주파수를 자동 추천합니다.',
          style: TextStyle(color: Colors.white60, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 8),
        if (sp != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(4),
              color: Colors.white.withValues(alpha: 0.02),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(sp.name,
                  style: const TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(
                'Fs ${sp.fs.toStringAsFixed(0)}Hz  ·  Qts ${sp.qts.toStringAsFixed(2)}  ·  Vas ${sp.vas.toStringAsFixed(1)}L  ·  Sens ${sp.sensitivity.toStringAsFixed(0)}dB',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                '추천 크로스오버: ${sp.recommendedCrossoverFreq.toStringAsFixed(0)}Hz (${sp.crossoverBasis})',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ]),
          ),
          const SizedBox(height: 6),
        ],
        GestureDetector(
          onTap: () => setState(() => _showTsInput = !_showTsInput),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(children: [
              const Icon(Icons.tune, color: Colors.white24, size: 13),
              const SizedBox(width: 8),
              Text(
                _showTsInput ? 'T/S 입력 닫기' : 'T/S 직접 입력',
                style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1),
              ),
              const Spacer(),
              Icon(_showTsInput ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white24, size: 14),
            ]),
          ),
        ),
        if (_showTsInput) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _TsField(label: 'Fs (Hz) *', ctrl: _fsCtrl, hint: '80')),
            const SizedBox(width: 8),
            Expanded(child: _TsField(label: 'Qts *', ctrl: _qtsCtrl, hint: '0.38')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _TsField(label: 'Vas (L)', ctrl: _vasCtrl, hint: '5.0')),
            const SizedBox(width: 8),
            Expanded(child: _TsField(label: 'Xmax (mm)', ctrl: _xmaxCtrl, hint: '5.0')),
          ]),
          const SizedBox(height: 8),
          _TsField(label: '감도 dB/W/m', ctrl: _sensCtrl, hint: '87'),
          const SizedBox(height: 4),
          const Text('* Fs·Qts 필수, 나머지 선택',
              style: TextStyle(color: Colors.white24, fontSize: 9)),
          if (_tsError != null) ...[
            const SizedBox(height: 4),
            Text(_tsError!, style: const TextStyle(color: Colors.redAccent, fontSize: 10)),
          ],
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _saveTs,
            child: Container(
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text('T/S 저장 → 크로스오버 자동 계산',
                  style: TextStyle(color: Colors.white, fontSize: 13, letterSpacing: 1)),
            ),
          ),
        ],
      ],
    );
  }
}

class _TsField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final String hint;
  const _TsField({required this.label, required this.ctrl, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1)),
      const SizedBox(height: 4),
      TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
        ),
      ),
    ]);
  }
}

class _FrdRow extends StatelessWidget {
  final String label;
  final String? fileName;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _FrdRow({required this.label, required this.onTap, this.fileName, this.onClear});
  @override
  Widget build(BuildContext context) {
    final hasFile = fileName != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: hasFile ? Colors.white24 : Colors.white10),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Icon(hasFile ? Icons.check_circle_outline : Icons.upload_file_outlined,
              color: hasFile ? Colors.white38 : Colors.white12, size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(
            hasFile ? fileName! : '$label FRD 불러오기',
            style: TextStyle(color: hasFile ? Colors.white38 : Colors.white24, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          )),
          if (hasFile && onClear != null)
            GestureDetector(onTap: onClear,
                child: const Icon(Icons.close, color: Colors.white24, size: 12)),
        ]),
      ),
    );
  }
}

/// 크로스오버 추천 카드 — 멀티웨이(crossoverPoints≥1) + SpeakerProfile 있을 때만 표시
class _CrossoverCard extends ConsumerStatefulWidget {
  final SpeakerProfile profile;
  final BleState bState;
  const _CrossoverCard({required this.profile, required this.bState});
  @override
  ConsumerState<_CrossoverCard> createState() => _CrossoverCardState();
}

class _CrossoverCardState extends ConsumerState<_CrossoverCard> {
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sys = ref.read(systemProfileProvider);
      final freq = widget.profile.recommendedCrossoverFreq;
      final map = Map<int, double>.from(ref.read(channelXoFreqProvider));
      for (int i = 0; i < sys.channels.length; i++) {
        map.putIfAbsent(i, () => freq);
      }
      ref.read(channelXoFreqProvider.notifier).state = map;
    });
  }

  Future<void> _applySensitivityMatch() async {
    final sys = ref.read(systemProfileProvider);
    final ble = ref.read(bleProvider.notifier);
    final profile = widget.profile;

    final wooferSens = profile.wooferFrd != null && profile.wooferFrd!.isNotEmpty
        ? FrdParser.calculateSensitivity(profile.wooferFrd!)
        : profile.sensitivity;
    final tweeterSens = profile.tweeterFrd != null && profile.tweeterFrd!.isNotEmpty
        ? FrdParser.calculateSensitivity(profile.tweeterFrd!)
        : null;

    if (tweeterSens == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('트위터 FRD 데이터가 필요합니다'),
          duration: Duration(seconds: 2),
        ));
      }
      return;
    }

    final minSens = wooferSens < tweeterSens ? wooferSens : tweeterSens;
    final adapter = sys.adapterFactory((frame) => ble.sendRawFrame(frame));
    final gainMap = ref.read(channelGainProvider);

    setState(() => _sending = true);
    for (int i = 0; i < sys.channels.length; i++) {
      final ch = sys.channels[i];
      final double sens;
      if (ch.type == ChannelType.woofer) {
        sens = wooferSens;
      } else if (ch.type == ChannelType.tweeter) {
        sens = tweeterSens;
      } else {
        continue;
      }
      final base = (minSens - sens).clamp(-40.0, 0.0);
      final offset = gainMap[i] ?? 0.0;
      await adapter.writeGain(i, (base + offset).clamp(-40.0, 0.0));
    }
    setState(() => _sending = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('감도 매칭 완료 — 기준 ${minSens.toStringAsFixed(1)} dB'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  Future<void> _applyCrossover() async {
    setState(() => _sending = true);
    final sys  = ref.read(systemProfileProvider);
    final ble  = ref.read(bleProvider.notifier);
    final freqMap = ref.read(channelXoFreqProvider);
    final fallback = widget.profile.recommendedCrossoverFreq;

    final adapter = sys.adapterFactory((frame) => ble.sendRawFrame(frame));
    for (int i = 0; i < sys.channels.length; i++) {
      final ch = sys.channels[i];
      final freq = freqMap[i] ?? fallback;
      CrossoverConfig? cfg;
      if (ch.type == ChannelType.woofer) {
        cfg = CrossoverConfig(side: FilterSide.lpf, freqHz: freq, slope: CrossoverSlope.lr4);
      } else if (ch.type == ChannelType.tweeter) {
        cfg = CrossoverConfig(side: FilterSide.hpf, freqHz: freq, slope: CrossoverSlope.lr4);
      }
      if (cfg != null) await adapter.writeCrossover(i, cfg);
    }
    setState(() => _sending = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('크로스오버 적용됨'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sys    = ref.watch(systemProfileProvider);
    final isConn = widget.bState.connection == BleConnectionState.connected;
    final basis  = widget.profile.crossoverBasis;
    final label  = widget.profile.hasFrd ? basis :
                   (widget.profile.qts < 0.4 ? '$basis · Fs × 20' :
                    widget.profile.qts < 0.7 ? '$basis · Fs × 28' : '$basis · Fs × 35');

    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('크로스오버', style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
          const Spacer(),
          OutlineButton(
            label: _sending ? '전송 중...' : 'APPLY',
            loading: _sending,
            enabled: isConn && !_sending,
            onTap: isConn && !_sending ? _applyCrossover : null,
          ),
        ]),
        const SizedBox(height: 4),
        Text('$label  ·  Fs ${widget.profile.fs.toStringAsFixed(0)} Hz  ·  LR4',
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        ...sys.bandPairs.map((band) => _BandLinkRow(
          band: band,
          sys: sys,
          fallbackFreq: widget.profile.recommendedCrossoverFreq,
        )),
        if (widget.profile.tweeterFrd != null && widget.profile.tweeterFrd!.isNotEmpty) ...[
          const Divider(color: Colors.white12, height: 20),
          Row(children: [
            const Text('감도 매칭',
                style: TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
            const Spacer(),
            OutlineButton(
              label: _sending ? '전송 중...' : '감도 매칭 적용',
              loading: _sending,
              enabled: isConn && !_sending,
              onTap: isConn && !_sending ? _applySensitivityMatch : null,
            ),
          ]),
        ],
        if (!isConn)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('스피커 연결 후 적용 가능합니다',
                style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
          ),
      ]),
    );
  }
}

class _BandLinkRow extends ConsumerWidget {
  final ({ChannelType type, int leftIdx, int rightIdx}) band;
  final SystemProfile sys;
  final double fallbackFreq;

  const _BandLinkRow({
    required this.band,
    required this.sys,
    required this.fallbackFreq,
  });

  String _bandLabel(ChannelType type) {
    switch (type) {
      case ChannelType.woofer:    return 'WOO';
      case ChannelType.mid:       return 'MID';
      case ChannelType.tweeter:   return 'TWE';
      case ChannelType.subwoofer: return 'SUB';
      case ChannelType.fullRange: return 'FUL';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linked   = ref.watch(channelLinkProvider)[band.type] ?? true;
    final hasRight = band.rightIdx >= 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_bandLabel(band.type),
            style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 2)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: _ChannelControl(
            label: 'L',
            channelIdx: band.leftIdx,
            sys: sys,
            fallbackFreq: fallbackFreq,
          )),
          if (hasRight) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => ref.toggleLink(band.type),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: linked
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.transparent,
                  border: Border.all(
                    color: linked ? Colors.white54 : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    linked ? '🔗' : '⛓️',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(child: _ChannelControl(
              label: 'R',
              channelIdx: band.rightIdx,
              sys: sys,
              fallbackFreq: fallbackFreq,
            )),
          ] else ...[
            const Expanded(child: SizedBox()),
          ],
        ]),
      ]),
    );
  }
}

class _ChannelControl extends ConsumerWidget {
  final String label;
  final int channelIdx;
  final SystemProfile sys;
  final double fallbackFreq;

  const _ChannelControl({
    required this.label,
    required this.channelIdx,
    required this.sys,
    required this.fallbackFreq,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gain = ref.watch(channelGainProvider)[channelIdx] ?? 0.0;
    final freq = ref.watch(channelXoFreqProvider)[channelIdx] ?? fallbackFreq;
    final ch   = sys.channels[channelIdx];

    final showFreq = ch.type != ChannelType.fullRange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 14,
                  letterSpacing: 1, fontWeight: FontWeight.bold)),
          const Spacer(),
          if (showFreq)
            GestureDetector(
              onTap: () => _editFreq(context, ref, freq, ch.type),
              child: Text('${freq.toStringAsFixed(0)} Hz',
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
        ]),
        Row(children: [
          const Text('GAIN', style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 1,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: Colors.white54,
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: Colors.white12,
              ),
              child: Slider(
                value: gain.clamp(-20.0, 6.0),
                min: -20.0,
                max: 6.0,
                onChanged: (v) => ref.setChannelGain(
                  channelIdx,
                  (v * 10).round() / 10,
                  sys: sys,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _editGain(context, ref, gain, ch.type),
            child: SizedBox(
              width: 44,
              child: Text(
                '${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}',
                textAlign: TextAlign.right,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Future<void> _editGain(
      BuildContext context, WidgetRef ref, double current, ChannelType type) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(1));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text('게인 ($label)', style: const TextStyle(color: Colors.white, fontSize: 14)),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            suffixText: 'dB',
            suffixStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.white38))),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null) Navigator.pop(ctx, v.clamp(-20.0, 6.0));
            },
            child: const Text('확인', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
    if (result != null) {
      ref.setChannelGain(channelIdx, result, sys: sys);
    }
  }

  Future<void> _editFreq(
      BuildContext context, WidgetRef ref, double current, ChannelType type) async {
    final ctrl = TextEditingController(text: current.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          '크로스오버 주파수 ($label)',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            suffixText: 'Hz',
            suffixStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.white54),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('확인', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
    if (result != null) {
      ref.setChannelXoFreq(channelIdx, result, sys: sys);
    }
  }
}
