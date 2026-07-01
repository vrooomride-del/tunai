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
import 'package:file_picker/file_picker.dart';
import '../../core/dsp/dsp_adapter.dart';
import '../../core/frd_parser.dart';
import '../../core/channel_link_provider.dart';
import 'package:permission_handler/permission_handler.dart';

// systemProfileProvider, speakerProfileProvider는 core에서 import됨
// (community_screen 등 다른 feature에서 순환 없이 접근 가능)

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mState = ref.watch(measurementProvider);
    final bState = ref.watch(bleProvider);

    // Bluetooth OFF 감지 → 안내 다이얼로그
    ref.listen<BleState>(bleProvider, (prev, next) {
      if (next.connection == BleConnectionState.bluetoothOff &&
          prev?.connection != BleConnectionState.bluetoothOff) {
        _showBluetoothOffDialog(context);
      }
    });

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
                    const _StepSection(index: 1, label: 'SELECT SPEAKER', active: true,
                        child: _SpeakerSelectPanel()),
                    Consumer(builder: (_, r, __) {
                      final sys = r.watch(systemProfileProvider);
                      final sp  = r.watch(speakerProfileProvider);
                      // 멀티웨이 + 스피커 프로파일이 있을 때만 크로스오버 카드 표시
                      if (sys.crossoverPoints < 1 || sp == null) return const SizedBox.shrink();
                      return Column(children: [
                        const SizedBox(height: 16),
                        _CrossoverCard(profile: sp, bState: r.watch(bleProvider)),
                      ]);
                    }),
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

Future<void> _showBluetoothOffDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text(
        '블루투스가 꺼져 있습니다',
        style: TextStyle(color: Colors.white, fontSize: 15),
      ),
      content: const Text(
        '블루투스가 꺼져 있습니다. 설정에서 켜주세요.',
        style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('닫기', style: TextStyle(color: Colors.white38)),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(ctx);
            await openAppSettings();
          },
          child: const Text('설정 열기', style: TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
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

class _SpeakerSelectPanel extends ConsumerStatefulWidget {
  const _SpeakerSelectPanel();
  @override
  ConsumerState<_SpeakerSelectPanel> createState() => _SpeakerSelectPanelState();
}

class _SpeakerSelectPanelState extends ConsumerState<_SpeakerSelectPanel> {
  String? _wooferFrdName;
  String? _tweeterFrdName;
  String? _frdError;

  // T/S 직접 입력 상태
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
        Text('${selected.channelCount}ch · 크로스오버 ${selected.crossoverPoints}개',
            style: const TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),

        // FRD 임포트 (프로파일 선택된 경우만)
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

        // ── T/S 직접 입력 ───────────────────────────────────────────
        const SizedBox(height: 14),
        const Divider(color: Colors.white12),
        const SizedBox(height: 10),
        // 안내 텍스트
        const Text(
          'T/S 파라미터 (선택)',
          style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2),
        ),
        const SizedBox(height: 4),
        const Text(
          'FRD/ZMA 파일 없어도 Fs·Qts만으로 크로스오버 주파수를 자동 추천합니다.',
          style: TextStyle(color: Colors.white24, fontSize: 10, height: 1.5),
        ),
        const SizedBox(height: 8),
        // 현재 T/S 요약 (저장된 경우)
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
                  style: const TextStyle(color: Colors.white60, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(
                'Fs ${sp.fs.toStringAsFixed(0)}Hz  ·  Qts ${sp.qts.toStringAsFixed(2)}  ·  Vas ${sp.vas.toStringAsFixed(1)}L  ·  Sens ${sp.sensitivity.toStringAsFixed(0)}dB',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 2),
              Text(
                '추천 크로스오버: ${sp.recommendedCrossoverFreq.toStringAsFixed(0)}Hz (${sp.crossoverBasis})',
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
            ]),
          ),
          const SizedBox(height: 6),
        ],
        // 입력 폼 토글 버튼
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
                  style: TextStyle(color: Colors.white, fontSize: 11, letterSpacing: 1)),
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
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
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

class _BlePanel extends StatelessWidget {
  final BleState bState; final WidgetRef ref;
  const _BlePanel({required this.bState, required this.ref});

  @override
  Widget build(BuildContext context) {
    final isScanning = bState.connection == BleConnectionState.scanning || bState.connection == BleConnectionState.connecting;
    final isConnected = bState.connection == BleConnectionState.connected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
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
      ]),

      // ADAU1466 탐지 배너 — PEQ/XO 주소 청감검증 진행 중
      if (bState.detectedBoard == DetectedBoard.adau1466) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withValues(alpha: 0.03),
          ),
          child: const Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white54, size: 14),
            SizedBox(width: 8),
            Expanded(child: Text(
              'ADAU1466 보드 연결됨. Gain/Delay 검증 완료 — PEQ/XO 주소 청감검증 진행 중.',
              style: TextStyle(color: Colors.white54, fontSize: 10, height: 1.5),
            )),
          ]),
        ),
      ],

      // 미식별 보드 배너
      if (isConnected && bState.detectedBoard == DetectedBoard.unknown) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(children: [
            Icon(Icons.help_outline, color: Colors.white38, size: 14),
            SizedBox(width: 8),
            Expanded(child: Text(
              '보드를 자동으로 식별하지 못했습니다. 설정에서 보드 종류를 직접 선택해 주세요.',
              style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
            )),
          ]),
        ),
      ],
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
    final isRunning = step != MeasurementStep.idle
        && step != MeasurementStep.done && step != MeasurementStep.error;
    final isConverging = step == MeasurementStep.converging;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text(
          mState.error ?? (mState.message.isEmpty ? '핑크노이즈 재생 후 공간 음향을 분석합니다.' : mState.message),
          style: TextStyle(color: mState.error != null ? Colors.redAccent : Colors.white38, fontSize: 13, height: 1.5))),
        const SizedBox(width: 16),
        _OutlineButton(
          label: isRunning ? (isConverging ? '수렴 중...' : '측정 중...') :
                 step == MeasurementStep.done ? 'RE-MEASURE' : 'MEASURE',
          loading: isRunning,
          onTap: isRunning ? null : step == MeasurementStep.done || step == MeasurementStep.error
            ? ctrl.reset
            : () => ctrl.startMeasurement(speakerProfile: ref.read(speakerProfileProvider)),
        ),
      ]),

      // Closed Loop 진행 상황
      if (isConverging && mState.iteration > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Expanded(child: LinearProgressIndicator(
              value: mState.iteration / 3,
              backgroundColor: Colors.white12,
              color: Colors.white38,
              minHeight: 2,
            )),
            const SizedBox(width: 12),
            Text('${mState.iteration}/3',
                style: const TextStyle(color: Colors.white38, fontSize: 10, letterSpacing: 1)),
            if (mState.residualErrorDb != null) ...[
              const SizedBox(width: 8),
              Text('잔류 ${mState.residualErrorDb!.toStringAsFixed(1)}dB',
                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
            ],
          ]),
        ),

      // 수렴 결과 배지
      if (step == MeasurementStep.done && mState.iteration > 0) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: mState.hasConverged ? Colors.white24 : Colors.white12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            Icon(mState.hasConverged ? Icons.check_circle_outline : Icons.info_outline,
                color: mState.hasConverged ? Colors.white54 : Colors.white24, size: 14),
            const SizedBox(width: 8),
            Text(
              mState.hasConverged
                  ? '수렴 완료 (${mState.iteration}회'
                    '${mState.residualErrorDb != null ? ', 잔류 ${mState.residualErrorDb!.toStringAsFixed(1)}dB' : ''})'
                  : '${mState.iteration}회 반복 완료 — 수동 미세 조정 가능',
              style: TextStyle(
                  color: mState.hasConverged ? Colors.white54 : Colors.white24,
                  fontSize: 10),
            ),
          ]),
        ),
      ],

      // Closed Loop 시작 버튼 (측정 전 + BLE 연결 시)
      if (step == MeasurementStep.idle) ...[
        const SizedBox(height: 10),
        Consumer(builder: (_, r, __) {
          final isConn = r.watch(bleProvider).connection == BleConnectionState.connected;
          return _OutlineButton(
            label: 'AUTO TUNE (반복수렴)',
            enabled: isConn,
            onTap: isConn
                ? () => ctrl.startClosedLoop(
                    speakerProfile: r.read(speakerProfileProvider))
                : null,
          );
        }),
        const SizedBox(height: 4),
        const Text('DSP 적용 후 자동 재측정, 최대 3회 반복',
            style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
      ],
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
    final chipHint = '${mState.packets.length}개 노치 필터 → ${profile.chipLabel} Safeload';
    final hint = !hasDsp ? '측정 후 DSP 필터가 생성됩니다.' : !isConnected ? '스피커를 연결하면 DSP를 적용할 수 있습니다.' : chipHint;
    final canApply = hasDsp && isConnected && !isSending;
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
      height: 220,
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
    // 채널 XO 주파수를 권장값으로 초기화
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
      // 채널별 커스텀 게인 오프셋 적용
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

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.03),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('크로스오버', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
          const Spacer(),
          _OutlineButton(
            label: _sending ? '전송 중...' : 'DSP에 적용',
            loading: _sending,
            enabled: isConn && !_sending,
            onTap: isConn && !_sending ? _applyCrossover : null,
          ),
        ]),
        const SizedBox(height: 4),
        Text('$label  ·  Fs ${widget.profile.fs.toStringAsFixed(0)} Hz  ·  LR4',
            style: const TextStyle(color: Colors.white24, fontSize: 10)),
        const SizedBox(height: 12),
        // ── 대역별 L/R 링크 컨트롤 ──────────────────────────────
        ...sys.bandPairs.map((band) => _BandLinkRow(
          band: band,
          sys: sys,
          fallbackFreq: widget.profile.recommendedCrossoverFreq,
        )),
        // ── 감도 매칭 ────────────────────────────────────────────
        if (widget.profile.tweeterFrd != null && widget.profile.tweeterFrd!.isNotEmpty) ...[
          const Divider(color: Colors.white12, height: 20),
          Row(children: [
            const Text('감도 매칭',
                style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
            const Spacer(),
            _OutlineButton(
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

// ── 대역별 L/R 링크 행 ────────────────────────────────────────────

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
            style: const TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 2)),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // L 채널
          Expanded(child: _ChannelControl(
            label: 'L',
            channelIdx: band.leftIdx,
            sys: sys,
            fallbackFreq: fallbackFreq,
          )),
          // 링크 토글 버튼
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
            // R 채널
            Expanded(child: _ChannelControl(
              label: 'R',
              channelIdx: band.rightIdx,
              sys: sys,
              fallbackFreq: fallbackFreq,
            )),
          ] else ...[
            // mono 채널 — R 없음
            const Expanded(child: SizedBox()),
          ],
        ]),
      ]),
    );
  }
}

// ── 채널 단위 컨트롤 (게인 슬라이더 + 주파수 표시) ────────────────

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

    // 크로스오버 주파수: woofer/tweeter/mid만 표시
    final showFreq = ch.type != ChannelType.fullRange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 라벨 + 주파수
        Row(children: [
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
          const Spacer(),
          if (showFreq)
            GestureDetector(
              onTap: () => _editFreq(context, ref, freq, ch.type),
              child: Text('${freq.toStringAsFixed(0)} Hz',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ),
        ]),
        // 게인 슬라이더
        Row(children: [
          const Text('GAIN', style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1)),
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
                style: const TextStyle(color: Colors.white54, fontSize: 11),
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
        style: const TextStyle(color: Colors.white, fontSize: 13),
        minLines: 2,
        maxLines: 4,
        decoration: const InputDecoration(
          labelText: 'AI에게 요청',
          labelStyle: TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
      const SizedBox(height: 8),
      // 빠른 선택 버튼
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
      _OutlineButton(
        label: _loading ? 'AI 분석 중...' : 'AI 튜닝 요청',
        loading: _loading,
        enabled: widget.mState.peaks.isNotEmpty,
        onTap: widget.mState.peaks.isEmpty ? null : _suggest,
      ),
      if (_result != null && !_result!.isError) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: Colors.white12), borderRadius: BorderRadius.circular(6)),
          child: Text(_result!.explanation, style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.7)),
        ),
        const SizedBox(height: 12),
        // 밴드 카드 — 세로 스크롤 가능한 리스트
        ..._result!.bands.asMap().entries.map((e) {
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
                // 밴드 번호
                SizedBox(
                  width: 24,
                  child: Text('${idx + 1}',
                      style: TextStyle(color: active ? Colors.white38 : Colors.white12,
                          fontSize: 11, fontFamily: 'monospace')),
                ),
                const SizedBox(width: 8),
                // Hz — 탭 편집
                Expanded(
                  flex: 3,
                  child: GestureDetector(
                    onTap: () => _editBandHz(idx, hz),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${hz.toStringAsFixed(0)} Hz',
                          style: TextStyle(color: active ? Colors.white : Colors.white38, fontSize: 14)),
                      const Text('FREQ', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                    ]),
                  ),
                ),
                // dB — 탭 편집
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _editBandDb(idx, db),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)} dB',
                          style: TextStyle(
                              color: active ? (db >= 0 ? Colors.white70 : Colors.white54) : Colors.white24,
                              fontSize: 13)),
                      const Text('GAIN', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                    ]),
                  ),
                ),
                // Q — 탭 편집
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () => _editBandQ(idx, q),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Q ${q.toStringAsFixed(2)}',
                          style: TextStyle(color: active ? Colors.white54 : Colors.white24, fontSize: 13)),
                      const Text('Q', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 1)),
                    ]),
                  ),
                ),
                // APPLY 버튼
                if (active && isConnected)
                  GestureDetector(
                    onTap: () => _applyBand(b, idx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(3)),
                      child: const Text('APPLY', style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 1)),
                    ),
                  ),
              ]),
            ),
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
