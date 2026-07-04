import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../ble/ble_controller.dart';
import '../../core/onboarding_storage.dart';
import '../../core/tone_generator.dart';
import '../../shared/widgets.dart';

/// CONNECT 탭 — 스피커 BLE 스캔/연결만 담당.
/// 연결 성공 시 [onConnected]로 MEASURE 탭 자동 전환을 요청한다.
class ConnectScreen extends ConsumerStatefulWidget {
  final VoidCallback onConnected;
  const ConnectScreen({super.key, required this.onConnected});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWelcome());
  }

  Future<void> _maybeShowWelcome() async {
    final seen = await OnboardingStorage.hasSeenWelcome();
    if (seen || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Welcome to TUNAI', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          "Let's make your speaker sound amazing.",
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('시작하기', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
    await OnboardingStorage.markWelcomeSeen();
  }

  /// 연결 성공 직후 테스트 톤(1kHz, 1초) 재생 → "들리나요?" 확인.
  /// YES면 MEASURE로 이동, NO면 트러블슈팅 안내 후 재시도/건너뛰기.
  Future<void> _runTestToneFlow() async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _TestToneDialog(),
    );
    if (proceed == true) widget.onConnected();
  }

  @override
  Widget build(BuildContext context) {
    final bState = ref.watch(bleProvider);

    ref.listen<BleState>(bleProvider, (prev, next) {
      if (next.connection == BleConnectionState.bluetoothOff &&
          prev?.connection != BleConnectionState.bluetoothOff) {
        _showBluetoothOffDialog(context);
      }
      if (next.connection == BleConnectionState.connected &&
          prev?.connection != BleConnectionState.connected) {
        _runTestToneFlow();
      }
    });

    final isScanning = bState.connection == BleConnectionState.scanning ||
        bState.connection == BleConnectionState.found ||
        bState.connection == BleConnectionState.connecting;
    final isConnected = bState.connection == BleConnectionState.connected;
    final notFound = bState.connection == BleConnectionState.notFound;
    // 스캔을 한번이라도 시작했는지 — 이 시점부터 단계별 체크리스트를 보여준다
    final showSteps = bState.connection != BleConnectionState.disconnected &&
        bState.connection != BleConnectionState.bluetoothOff;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            const TunaiTopBar(subtitle: 'CONNECT'),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SectionCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Row(children: [
                          Expanded(child: Text(bState.message.isEmpty ? 'TUNAI 스피커를 검색합니다.' : bState.message,
                              style: const TextStyle(color: Colors.white60, fontSize: 14, height: 1.5))),
                          const SizedBox(width: 16),
                          OutlineButton(
                            label: isConnected ? 'DISCONNECT' : isScanning ? 'SCANNING...' : 'SCAN',
                            loading: isScanning,
                            onTap: isScanning ? null : isConnected
                                ? () => ref.read(bleProvider.notifier).disconnect()
                                : () => ref.read(bleProvider.notifier).scanAndConnect(),
                          ),
                        ]),

                        if (showSteps && !isConnected) ...[
                          const SizedBox(height: 12),
                          _ConnectSteps(state: bState.connection),
                        ],

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
                                style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
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
                                '보드를 자동으로 식별하지 못했습니다. ADVANCED에서 보드 종류를 직접 선택해 주세요.',
                                style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
                              )),
                            ]),
                          ),
                        ],
                      ]),
                    ),

                    if (notFound) ...[
                      const SizedBox(height: 16),
                      _ScanFailureGuide(onRetry: () => ref.read(bleProvider.notifier).scanAndConnect()),
                    ],

                    if (isConnected) ...[
                      const SizedBox(height: 16),
                      _ConnectedInfoCard(
                        deviceName: bState.deviceName,
                        onStartAiSetup: widget.onConnected,
                      ),
                    ],
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

/// CONNECT 진행상태 체크리스트 — Bluetooth ON / Speaker Found / Connecting / Connected
class _ConnectSteps extends StatelessWidget {
  final BleConnectionState state;
  const _ConnectSteps({required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state == BleConnectionState.scanning ||
        state == BleConnectionState.found ||
        state == BleConnectionState.connecting;

    final steps = <(String, bool)>[
      ('Bluetooth ON', state != BleConnectionState.bluetoothOff),
      ('Speaker Found', state == BleConnectionState.found ||
          state == BleConnectionState.connecting ||
          state == BleConnectionState.connected),
      ('Connecting...', state == BleConnectionState.connecting ||
          state == BleConnectionState.connected),
      ('Connected', state == BleConnectionState.connected),
    ];
    final currentIdx = steps.indexWhere((s) => !s.$2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 16,
                height: 16,
                child: steps[i].$2
                    ? const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16)
                    : (active && i == currentIdx)
                        ? const Padding(
                            padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
                          )
                        : const Icon(Icons.circle_outlined, color: Colors.white24, size: 14),
              ),
              const SizedBox(width: 8),
              Text(steps[i].$1,
                  style: TextStyle(
                      color: steps[i].$2 || (active && i == currentIdx) ? Colors.white70 : Colors.white24,
                      fontSize: 12)),
            ]),
          ),
      ],
    );
  }
}

/// 연결 완료 후 확장 정보 카드 — 기기명 / Ready 상태 / AI Setup 시작 버튼
/// (Firmware 버전: 현재 BLE로 읽는 경로가 없어 생략 — fff1 특성 페이로드 확인 후 추가 예정)
class _ConnectedInfoCard extends StatelessWidget {
  final String? deviceName;
  final VoidCallback onStartAiSetup;
  const _ConnectedInfoCard({required this.deviceName, required this.onStartAiSetup});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 40, height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(20)),
            child: const Icon(Icons.speaker, color: Colors.white70, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(deviceName ?? 'TUNAI 스피커', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              const Row(children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 12),
                SizedBox(width: 4),
                Text('Ready', style: TextStyle(color: Colors.greenAccent, fontSize: 11, letterSpacing: 1)),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        OutlineButton(label: 'Start AI Setup', onTap: onStartAiSetup),
      ]),
    );
  }
}

/// 검색 실패 가이드 — 일정 시간 스캔했는데도 못 찾았을 때 안내
class _ScanFailureGuide extends StatelessWidget {
  final VoidCallback onRetry;
  const _ScanFailureGuide({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text("Can't find your speaker?", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 10),
        const _GuideTip(text: 'Turn on speaker — 스피커 전원이 켜져 있는지 확인하세요'),
        const _GuideTip(text: 'Move closer — 스피커와 더 가까이서 시도해보세요'),
        const SizedBox(height: 12),
        OutlineButton(label: 'Setup New Speaker', onTap: onRetry),
      ]),
    );
  }
}

class _GuideTip extends StatelessWidget {
  final String text;
  const _GuideTip({required this.text});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ', style: TextStyle(color: Colors.white38, fontSize: 12)),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4))),
      ]),
    );
  }
}

/// 연결 직후 테스트 톤(1kHz, 1초) 재생 확인 다이얼로그.
/// pop(true) → MEASURE로 진행, pop(null/false 없음) → 안 닫힘(재시도/건너뛰기로만 진행)
class _TestToneDialog extends StatefulWidget {
  const _TestToneDialog();
  @override
  State<_TestToneDialog> createState() => _TestToneDialogState();
}

class _TestToneDialogState extends State<_TestToneDialog> {
  final _player = AudioPlayer();
  bool _playing = true;
  bool _showTrouble = false;
  String? _playError;

  @override
  void initState() {
    super.initState();
    _play();
  }

  Future<void> _play() async {
    setState(() { _playing = true; _showTrouble = false; _playError = null; });
    try {
      final bytes = const ToneGenerator(frequencyHz: 1000, durationSeconds: 1).generateWav();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/tunai_test_tone.wav');
      await file.writeAsBytes(bytes);
      await _player.setFilePath(file.path);
      await _player.play();
      await Future.delayed(const Duration(milliseconds: 1000));
    } catch (e) {
      _playError = '$e';
    }
    if (mounted) setState(() => _playing = false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: const Text('Test Tone', style: TextStyle(color: Colors.white, fontSize: 16)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _playing ? '1kHz 테스트 톤 재생 중...' : '들리나요?',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        if (_playError != null) ...[
          const SizedBox(height: 8),
          Text('재생 오류: $_playError', style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
        ],
        if (_showTrouble) ...[
          const SizedBox(height: 12),
          const Text('확인해보세요:', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          const Text(
            '• 스피커 볼륨이 켜져 있는지 확인\n• 스피커 전원/연결 케이블 확인\n• 앰프 입력 소스가 맞는지 확인',
            style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
          ),
        ],
      ]),
      actions: [
        if (_showTrouble)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('건너뛰기', style: TextStyle(color: Colors.white24)),
          ),
        if (_showTrouble)
          TextButton(onPressed: _play, child: const Text('다시 시도', style: TextStyle(color: Colors.white70))),
        if (!_playing) ...[
          TextButton(
            onPressed: () => setState(() => _showTrouble = true),
            child: const Text('NO', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('YES', style: TextStyle(color: Colors.white)),
          ),
        ],
      ],
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
