import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../ble/ble_controller.dart';
import '../../core/tone_generator.dart';
import '../../shared/first_run_guide_card.dart';
import '../../core/consumer_input_source.dart';

/// CONNECT 탭 — 스피커 BLE 스캔/연결만 담당.
/// 연결 성공 시 [onConnected]로 MEASURE 탭 자동 전환을 요청한다.
class ConnectScreen extends ConsumerStatefulWidget {
  final VoidCallback onConnected;
  final void Function(int)? onGoTo;
  const ConnectScreen({super.key, required this.onConnected, this.onGoTo});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  bool _isKo(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'ko';

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
    final ko = _isKo(context);

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
    final isIdle = bState.connection == BleConnectionState.disconnected;

    final goTo = widget.onGoTo ?? (_) {};

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: isConnected
            ? _ConnectedView(
                deviceName: bState.deviceName,
                onStartMeasure: widget.onConnected,
                ko: ko,
                onGoTo: goTo,
              )
            : Column(
                children: [
                  // ── 퍼스트런 안내 카드 ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FirstRunGuideCard(onGoTo: goTo),
                  ),

                  // ── 상단 헤더 ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ko
                              ? 'TUNAI 스피커를 찾고 있습니다'
                              : 'Looking for your TUNAI speaker',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w300,
                            height: 1.35,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          ko
                              ? '스피커 전원이 켜져 있고 가까이에 있는지 확인해주세요.\n연결이 완료되면 TUNAI가 당신의 공간을 학습합니다.'
                              : 'Make sure your speaker is powered on and nearby.\nOnce connected, TUNAI will learn your room.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 14,
                            height: 1.65,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  // ── 스캔 상태 ─────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isScanning) ...[
                            _ScanningAnimation(
                              message: bState.message.isEmpty
                                  ? (ko ? '검색 중...' : 'Scanning...')
                                  : bState.message,
                            ),
                          ],

                          if (notFound) ...[
                            _ScanFailureGuide(
                              ko: ko,
                              onRetry: () =>
                                  ref.read(bleProvider.notifier).scanAndConnect(),
                            ),
                          ],

                          if (bState.detectedBoard == DetectedBoard.adau1466) ...[
                            const SizedBox(height: 24),
                            _BoardBanner(
                              text: ko
                                  ? 'TUNAI ONE이 준비되었습니다. 이제 Room Scan을 시작할 수 있습니다.'
                                  : 'TUNAI ONE is ready. You can start Room Scan now.',
                              color: Colors.white24,
                              icon: Icons.check_circle_outline,
                            ),
                          ],

                          const SizedBox(height: 32),
                          _InputSourceSection(ko: ko, isConnected: false),

                        ],
                      ),
                    ),
                  ),

                  // ── 하단 버튼 ─────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
                    child: Column(
                      children: [
                        if (isScanning)
                          _FullWidthButton(
                            label: ko ? '검색 중...' : 'Scanning...',
                            filled: false,
                            onTap: null,
                          )
                        else if (isIdle || notFound)
                          _FullWidthButton(
                            label: ko ? '스캔 시작' : 'Start Scan',
                            onTap: () =>
                                ref.read(bleProvider.notifier).scanAndConnect(),
                          ),
                        if (isScanning || !isIdle) ...[
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: () =>
                                ref.read(bleProvider.notifier).disconnect(),
                            child: Text(
                              ko ? '취소' : 'Cancel',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.3),
                                fontSize: 13,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Connected 전체화면 뷰 ─────────────────────────────────────────────────────
class _ConnectedView extends StatelessWidget {
  final String? deviceName;
  final VoidCallback onStartMeasure;
  final bool ko;
  final void Function(int) onGoTo;
  const _ConnectedView(
      {required this.deviceName, required this.onStartMeasure, required this.ko, required this.onGoTo});

  @override
  Widget build(BuildContext context) {
    final name = deviceName ?? 'TUNAI ONE';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FirstRunGuideCard(onGoTo: onGoTo),
          const SizedBox(height: 8),
          _ConnectedBody(name: name, onStartMeasure: onStartMeasure, ko: ko),
        ],
      ),
    );
  }
}

class _ConnectedBody extends StatelessWidget {
  final String name;
  final VoidCallback onStartMeasure;
  final bool ko;
  const _ConnectedBody({required this.name, required this.onStartMeasure, required this.ko});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 연결 상태 인디케이터
          Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFF69F0AE),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              ko ? '연결됨' : 'Connected',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                letterSpacing: 1.5,
              ),
            ),
          ]),
          const SizedBox(height: 28),

          // 타이틀
          Text(
            ko ? '$name이 연결되었습니다.' : '$name is connected.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w300,
              height: 1.35,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            ko
                ? '이제 당신의 공간을 알려주세요.'
                : "Now let's create a sound profile for your room.",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 15,
              height: 1.6,
            ),
          ),

          const SizedBox(height: 32),

          _FullWidthButton(
            label: ko ? '공간 스캔 시작' : 'Start Room Scan',
            onTap: onStartMeasure,
          ),
          const SizedBox(height: 36),
          _InputSourceSection(ko: ko, isConnected: true),
        ],
      ),
    );
  }
}

// ── 스캔 중 애니메이션 ─────────────────────────────────────────────────────────
class _ScanningAnimation extends StatefulWidget {
  final String message;
  const _ScanningAnimation({required this.message});
  @override
  State<_ScanningAnimation> createState() => _ScanningAnimationState();
}

class _ScanningAnimationState extends State<_ScanningAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _fade = Tween<double>(begin: 0.2, end: 0.8).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FadeTransition(
          opacity: _fade,
          child: Row(children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              widget.message,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 13,
                  letterSpacing: 0.3),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ── 검색 실패 가이드 ───────────────────────────────────────────────────────────
class _ScanFailureGuide extends StatelessWidget {
  final bool ko;
  final VoidCallback onRetry;
  const _ScanFailureGuide({required this.ko, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        ko ? '스피커를 찾지 못했습니다' : "Can't find your speaker?",
        style: const TextStyle(
            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w400),
      ),
      const SizedBox(height: 16),
      _Tip(ko ? '스피커 전원이 켜져 있는지 확인해주세요' : 'Turn on speaker and check the power cable'),
      _Tip(ko ? '스피커와 더 가까이서 시도해보세요' : 'Move closer to your speaker'),
      _Tip(ko ? '블루투스가 켜져 있는지 확인해주세요' : 'Make sure Bluetooth is enabled'),
    ]);
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('— ', style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 13)),
        Expanded(
            child: Text(text,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 13,
                    height: 1.5))),
      ]),
    );
  }
}

// ── 보드 배너 ─────────────────────────────────────────────────────────────────
class _BoardBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _BoardBanner({required this.text, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 11, height: 1.5))),
      ]),
    );
  }
}

// ── 공용 버튼 ─────────────────────────────────────────────────────────────────
class _FullWidthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _FullWidthButton({required this.label, this.onTap, this.filled = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: filled && onTap != null ? Colors.white : Colors.transparent,
          border: filled && onTap != null
              ? null
              : Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(4),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: filled && onTap != null
                ? Colors.black
                : Colors.white.withValues(alpha: 0.4),
            fontSize: 14,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.5,
          ),
        ),
      ),
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
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      title: Text(
        ko ? '소리 확인' : 'Sound Check',
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          _playing
              ? (ko ? '처음 소리는 낮은 볼륨에서 시작됩니다.' : 'The first sound starts at a safe volume.')
              : (ko ? '스피커에서 짧은 소리가 들리나요?' : 'Do you hear the test sound from your speaker?'),
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
        ),
        if (_playError != null) ...[
          const SizedBox(height: 8),
          Text(
            ko ? '재생 오류: $_playError' : 'Playback error: $_playError',
            style: const TextStyle(color: Colors.redAccent, fontSize: 11),
          ),
        ],
        if (_showTrouble) ...[
          const SizedBox(height: 12),
          Text(
            ko ? '확인해보세요:' : 'Try these steps:',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            ko
                ? '• 스피커 볼륨이 켜져 있는지 확인\n• 스피커 전원/연결 케이블 확인\n• 앰프 입력 소스가 맞는지 확인'
                : '• Check that the speaker volume is on\n• Check speaker power and cables\n• Make sure the amplifier input is correct',
            style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.6),
          ),
        ],
      ]),
      actions: [
        if (_showTrouble)
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(ko ? '건너뛰기' : 'Skip', style: const TextStyle(color: Colors.white24)),
          ),
        if (_showTrouble)
          TextButton(
            onPressed: _play,
            child: Text(ko ? '다시 시도' : 'Try Again', style: const TextStyle(color: Colors.white70)),
          ),
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

// ── Input Source Section ───────────────────────────────────────────────────────

class _InputSourceSection extends ConsumerWidget {
  final bool ko;
  final bool isConnected;
  const _InputSourceSection({required this.ko, required this.isConnected});

  String _description(ConsumerInputSource source, bool ko) => switch (source) {
        ConsumerInputSource.auto => ko
            ? 'TUNAI가 사용 가능한 입력을 자동으로 선택합니다.'
            : 'TUNAI selects the available input automatically.',
        ConsumerInputSource.bluetooth => ko
            ? '휴대폰이나 플레이어의 Bluetooth 소리를 사용합니다.'
            : 'Use sound from your phone or player over Bluetooth.',
        ConsumerInputSource.aux => ko
            ? '케이블로 연결된 소리를 사용합니다.'
            : 'Use sound from a cable connection.',
      };

  void _select(BuildContext context, WidgetRef ref, ConsumerInputSource source) {
    ref.read(selectedInputSourceProvider.notifier).state = source;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        ko
            ? '현재 버전에서는 입력 상태 표시용입니다.'
            : 'This version shows input preference only.',
        style: const TextStyle(color: Colors.white70, fontSize: 13),
      ),
      backgroundColor: const Color(0xFF1A1A1A),
      duration: const Duration(seconds: 3),
    ));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ko ? '입력 소스' : 'Input Source',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (!isConnected) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              ko
                  ? '스피커를 연결하면 입력 소스를 확인할 수 있습니다.'
                  : 'Connect your speaker to view input source options.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.28),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ] else ...[
          Builder(builder: (context) {
            final selected = ref.watch(selectedInputSourceProvider);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _InputChip(
                    label: ko ? '자동' : 'Auto',
                    isSelected: selected == ConsumerInputSource.auto,
                    onTap: () => _select(context, ref, ConsumerInputSource.auto),
                  ),
                  const SizedBox(width: 8),
                  _InputChip(
                    label: 'Bluetooth',
                    isSelected: selected == ConsumerInputSource.bluetooth,
                    onTap: () => _select(context, ref, ConsumerInputSource.bluetooth),
                  ),
                  const SizedBox(width: 8),
                  _InputChip(
                    label: 'AUX',
                    isSelected: selected == ConsumerInputSource.aux,
                    onTap: () => _select(context, ref, ConsumerInputSource.aux),
                  ),
                ]),
                const SizedBox(height: 10),
                Text(
                  _description(selected, ko),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            );
          }),
        ],
      ],
    );
  }
}

class _InputChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _InputChip({required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.07) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.white54 : Colors.white.withValues(alpha: 0.15),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.38),
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
