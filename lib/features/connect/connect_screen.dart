import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble/ble_controller.dart';
import '../ble/consumer_product_identity.dart';

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
  // ConsumerBleService's own retry loop can legitimately take up to ~15s
  // (1+2+4+8s backoff) before it gives up and reports failure — during that
  // whole window the UI used to show nothing but a generic "연결 중..."
  // spinner with no explanation, which read as an indefinite hang (the
  // actual real-device complaint: "원인을 알 수 없음"). This timer surfaces
  // an honest "this is taking a while, check your speaker" message partway
  // through that same window instead of adding any new waiting.
  static const _delayedGuidanceThreshold = Duration(seconds: 6);
  Timer? _delayedGuidanceTimer;
  bool _showDelayedGuidance = false;

  void _armDelayedGuidance() {
    _delayedGuidanceTimer?.cancel();
    setState(() => _showDelayedGuidance = false);
    _delayedGuidanceTimer = Timer(_delayedGuidanceThreshold, () {
      if (mounted) setState(() => _showDelayedGuidance = true);
    });
  }

  void _disarmDelayedGuidance() {
    _delayedGuidanceTimer?.cancel();
    _delayedGuidanceTimer = null;
    if (_showDelayedGuidance) setState(() => _showDelayedGuidance = false);
  }

  @override
  void dispose() {
    _delayedGuidanceTimer?.cancel();
    super.dispose();
  }
  bool _isKo(BuildContext ctx) =>
      Localizations.localeOf(ctx).languageCode == 'ko';

  @override
  Widget build(BuildContext context) {
    final bState = ref.watch(bleProvider);
    final ko = _isKo(context);

    ref.listen<BleState>(bleProvider, (prev, next) {
      if (next.connection == BleConnectionState.bluetoothOff &&
          prev?.connection != BleConnectionState.bluetoothOff) {
        _showBluetoothOffDialog(context);
      }
      final wasWaiting = prev?.connection == BleConnectionState.connecting ||
          prev?.connection == BleConnectionState.reconnecting;
      final nowWaiting = next.connection == BleConnectionState.connecting ||
          next.connection == BleConnectionState.reconnecting;
      if (nowWaiting && !wasWaiting) {
        _armDelayedGuidance();
      } else if (!nowWaiting && wasWaiting) {
        _disarmDelayedGuidance();
      }
    });

    final isScanning = bState.connection == BleConnectionState.scanning;
    final isConnecting = bState.connection == BleConnectionState.connecting;
    final isReconnecting = bState.connection == BleConnectionState.reconnecting;
    final deviceFound = bState.connection == BleConnectionState.found;
    final isConnected = bState.connection == BleConnectionState.connected;
    final notFound = bState.connection == BleConnectionState.notFound;
    final isIdle = bState.connection == BleConnectionState.disconnected;
    final hasSafeError = bState.connection == BleConnectionState.error ||
        bState.connection == BleConnectionState.permissionRequired ||
        bState.connection == BleConnectionState.bluetoothOff ||
        bState.connection == BleConnectionState.unsupported ||
        bState.connection == BleConnectionState.connectionLost;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: isConnected
            ? _ConnectedLayout(
                deviceName: bState.deviceName,
                detectedBoard: bState.detectedBoard,
                onStartMeasure: widget.onConnected,
                onDisconnect: () => ref.read(bleProvider.notifier).disconnect(),
                onForget: () => ref.read(bleProvider.notifier).forgetDevice(),
                ko: ko,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── 비대화형 단계 진행 표시 ────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
                    child: _StepProgress(
                      step1Done: false,
                      step2Active: false,
                      ko: ko,
                    ),
                  ),

                  const SizedBox(height: 38),

                  // ── 안내 카드 (버튼 없음) ─────────────────────────
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: _ConnectInfoCard(ko: ko),
                  ),

                  const SizedBox(height: 34),

                  // ── 스캔 상태 ─────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isScanning || isConnecting || isReconnecting) ...[
                            _ScanningAnimation(
                              message: isConnecting || isReconnecting
                                  ? (ko ? '스피커 연결을 준비하고 있습니다.' : 'Preparing to connect your speaker.')
                                  : (ko ? '검색 중...' : 'Searching...'),
                            ),
                            if ((isConnecting || isReconnecting) &&
                                _showDelayedGuidance) ...[
                              const SizedBox(height: 16),
                              _DelayedConnectionNotice(
                                ko: ko,
                                onRetry: () {
                                  ref.read(bleProvider.notifier).disconnect();
                                  ref.read(bleProvider.notifier).scan();
                                },
                              ),
                            ],
                          ],
                          if (deviceFound) ...[
                            Text(
                              ko ? '스피커를 선택해주세요' : 'Select your speaker',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              key: const Key('consumer_ble_device_selector'),
                              value: bState.selectedDeviceIdentifier,
                              isExpanded: true,
                              dropdownColor: const Color(0xFF181818),
                              decoration: InputDecoration(
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.white54),
                                ),
                              ),
                              style: const TextStyle(color: Colors.white),
                              items: bState.devices
                                  .map(
                                    (device) => DropdownMenuItem<String>(
                                      value: device.identifier,
                                      child: Row(children: [
                                        Expanded(
                                            child: Text(
                                          ConsumerProductIdentity
                                              .fromPhysicalIdentity(
                                            physicalDeviceName: device.name,
                                            supportedProfileValidated: false,
                                          ).displayName,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        )),
                                        if (device.rssi != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            ConsumerProductIdentity
                                                .signalQuality(device.rssi,
                                                    ko: ko),
                                            maxLines: 1,
                                            style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12),
                                          ),
                                        ],
                                      ]),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (identifier) {
                                if (identifier != null) {
                                  ref
                                      .read(bleProvider.notifier)
                                      .selectDevice(identifier);
                                }
                              },
                            ),
                          ],
                          if (notFound) ...[
                            _ScanFailureGuide(
                              ko: ko,
                              onRetry: () => ref
                                  .read(bleProvider.notifier)
                                  .scanAndConnect(),
                            ),
                          ],
                          if (hasSafeError) ...[
                            _SafeConnectionMessage(
                              text: _safeConnectionText(
                                bState.connection,
                                ko: ko,
                              ),
                            ),
                          ],
                          // A failed auto-reconnect (cold start with a known
                          // speaker) lands here as plain `disconnected`, not
                          // `connectionLost` — this is exactly the real-device
                          // complaint ("연결 실패, 원인을 알 수 없음"): without
                          // this, the screen looked identical to a first-time
                          // connect with no acknowledgment that a saved
                          // speaker just failed to reconnect.
                          if (isIdle && bState.hasKnownDevice) ...[
                            _SafeConnectionMessage(
                              text: ko
                                  ? '저장된 스피커에 연결하지 못했습니다. 스피커 전원이 켜져 있는지 확인하고 다시 시도해주세요.'
                                  : "Couldn't connect to your saved speaker. "
                                      'Check that it\'s powered on and try again.',
                            ),
                          ],
                          if (bState.detectedBoard ==
                              DetectedBoard.adau1466) ...[
                            const SizedBox(height: 24),
                            _BoardBanner(
                              text: ko
                                  ? 'TUNAI ONE이 준비되었습니다. 이제 공간 분석을 시작할 수 있습니다.'
                                  : 'TUNAI ONE is ready. You can start Space Analysis now.',
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

                  // ── 하단 단일 CTA ─────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
                    child: Column(
                      children: [
                        if (isScanning || isConnecting || isReconnecting)
                          _FullWidthButton(
                            label: isReconnecting
                                ? (ko ? '재연결 중...' : 'Reconnecting...')
                                : isConnecting
                                    ? (ko ? '연결 중...' : 'Connecting...')
                                    : (ko ? '검색 중...' : 'Searching...'),
                            filled: false,
                            onTap: null,
                          )
                        else if (deviceFound)
                          _FullWidthButton(
                            key: const Key('consumer_ble_connect_button'),
                            label: ko ? '연결' : 'Connect',
                            onTap: bState.selectedDeviceIdentifier == null
                                ? null
                                : () => ref
                                    .read(bleProvider.notifier)
                                    .connectSelected(),
                          )
                        else if (isIdle || notFound || hasSafeError)
                          _FullWidthButton(
                            key: const Key('consumer_ble_scan_button'),
                            label: ko ? '스피커 연결하기' : 'Connect Speaker',
                            onTap: () => ref.read(bleProvider.notifier).scan(),
                          ),
                        if (!isConnected &&
                            bState.hasKnownDevice &&
                            !isScanning &&
                            !isConnecting &&
                            !isReconnecting) ...[
                          const SizedBox(height: 8),
                          TextButton(
                            key: const Key('consumer_ble_forget_saved_button'),
                            onPressed: () =>
                                ref.read(bleProvider.notifier).forgetDevice(),
                            child: Text(
                              ko ? '저장된 스피커 지우기' : 'Forget saved speaker',
                              style: const TextStyle(color: Colors.white38),
                            ),
                          ),
                        ],
                        if (isScanning ||
                            isConnecting ||
                            isReconnecting ||
                            deviceFound) ...[
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

// ── 연결됨 전체 레이아웃 ─────────────────────────────────────────────────────────
class _ConnectedLayout extends StatelessWidget {
  final String? deviceName;
  final DetectedBoard? detectedBoard;
  final VoidCallback onStartMeasure;
  final VoidCallback onDisconnect;
  final VoidCallback onForget;
  final bool ko;
  const _ConnectedLayout({
    required this.deviceName,
    required this.detectedBoard,
    required this.onStartMeasure,
    required this.onDisconnect,
    required this.onForget,
    required this.ko,
  });

  @override
  Widget build(BuildContext context) {
    final name = deviceName ?? 'TUNAI ONE';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── 단계 진행 (1단계 완료, 2단계 활성) ──────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 30, 28, 0),
          child: _StepProgress(
            step1Done: true,
            step2Active: true,
            ko: ko,
          ),
        ),

        const SizedBox(height: 38),

        // ── 연결됨 정보 + 보조 액션 (스크롤 가능) ────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 연결 상태 인디케이터
                Row(
                  children: [
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
                      ko ? '연결됨 ✓' : 'Connected ✓',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    height: 1.35,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ko
                      ? '나만의 사운드를 만들 준비가 되었습니다.'
                      : 'Ready to create your personal sound.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),

                // "Connected" (isConnected==true, the only way this layout
                // renders) is only ever reached after the BLE identity
                // handshake succeeds (see ConsumerBleService._connectAndValidate
                // — `status: connected` is set strictly after
                // `_supportedIdentityValidated = true`). So reaching this
                // screen already means the product is identified and its DSP
                // command channel is ready — that must be visible here
                // directly, not gated on the separate/fragile `detectedBoard`
                // signal (previously required `== DetectedBoard.adau1466`,
                // which could leave a genuinely ready speaker showing no
                // readiness indicator at all).
                const SizedBox(height: 20),
                _BoardBanner(
                  text: ko
                      ? '제품이 확인되었고 사용 준비가 되었습니다. 이제 공간 분석을 시작할 수 있습니다.'
                      : 'Your speaker is identified and ready. You can start Space Analysis now.',
                  color: Colors.white24,
                  icon: Icons.check_circle_outline,
                ),

                const SizedBox(height: 28),
                _InputSourceSection(ko: ko, isConnected: true),

                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      key: const Key('consumer_ble_disconnect_button'),
                      onTap: onDisconnect,
                      child: Text(
                        ko ? '연결 해제' : 'Disconnect',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    Text(
                      '  ·  ',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.15),
                          fontSize: 13),
                    ),
                    GestureDetector(
                      key: const Key('consumer_ble_forget_button'),
                      onTap: onForget,
                      child: Text(
                        ko ? '스피커 지우기' : 'Forget Speaker',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.3),
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ── 단일 기본 CTA ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 12, 28, 36),
          child: _FullWidthButton(
            key: const Key('consumer_start_room_button'),
            label: ko ? '공간 분석하기' : 'Analyze Your Space',
            onTap: onStartMeasure,
          ),
        ),
      ],
    );
  }
}

// ── 비대화형 단계 진행 표시 ───────────────────────────────────────────────────────
class _StepProgress extends StatelessWidget {
  final bool step1Done;
  final bool step2Active;
  final bool ko;
  const _StepProgress({
    required this.step1Done,
    required this.step2Active,
    required this.ko,
  });

  @override
  Widget build(BuildContext context) {
    final step1Active = !step1Done;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepRow(
          number: '1',
          label: ko ? '스피커 연결' : 'Connect Speaker',
          done: step1Done,
          active: step1Active,
        ),
        const SizedBox(height: 14),
        _StepRow(
          number: '2',
          label: ko ? '공간 분석' : 'Space Analysis',
          done: false,
          active: step2Active,
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String label;
  final bool done;
  final bool active;
  const _StepRow({
    required this.number,
    required this.label,
    required this.done,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final circleColor = done
        ? const Color(0xFF69F0AE)
        : active
            ? Colors.white
            : Colors.transparent;
    final circleBorder =
        done || active ? null : Border.all(color: Colors.white24);
    final numberColor = done
        ? Colors.black
        : active
            ? Colors.black
            : Colors.white24;
    final labelColor =
        done || active ? Colors.white : Colors.white.withValues(alpha: 0.3);

    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: circleColor,
            border: circleBorder,
          ),
          alignment: Alignment.center,
          child: done
              ? const Icon(Icons.check, size: 12, color: Colors.black)
              : Text(
                  number,
                  style: TextStyle(
                    color: numberColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 15,
              fontWeight: FontWeight.w300,
              letterSpacing: 0.1,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── 안내 카드 (버튼 없음) ─────────────────────────────────────────────────────────
class _ConnectInfoCard extends StatelessWidget {
  final bool ko;
  const _ConnectInfoCard({required this.ko});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('consumer_connect_info_card'),
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko ? 'TUNAI 스피커를 연결해주세요.' : 'Connect your TUNAI speaker.',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w300,
              height: 1.2,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            ko
                ? '스피커를 연결하면 공간 분석을 시작할 수 있습니다.'
                : 'Space analysis becomes available after connection.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 연결 지연 안내 (무한 대기처럼 보이지 않도록) ───────────────────────────────
class _DelayedConnectionNotice extends StatelessWidget {
  final bool ko;
  final VoidCallback onRetry;
  const _DelayedConnectionNotice({required this.ko, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(8),
        color: Colors.white.withValues(alpha: 0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ko
                ? '스피커 연결이 지연되고 있습니다.\n스피커 전원이 켜져 있는지 확인해주세요.'
                : "Your speaker connection is taking longer than usual.\n"
                    'Please check that your speaker is powered on.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            key: const Key('consumer_ble_delayed_retry_button'),
            onTap: onRetry,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                ko ? '다시 연결' : 'Reconnect',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
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
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _fade = Tween<double>(
      begin: 0.2,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
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
      child: FadeTransition(
        opacity: _fade,
        child: Row(
          children: [
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
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 검색 실패 가이드 ───────────────────────────────────────────────────────────
String _safeConnectionText(BleConnectionState state, {required bool ko}) =>
    switch (state) {
      BleConnectionState.bluetoothOff =>
        ko ? '블루투스를 사용할 수 없습니다.' : 'Bluetooth unavailable',
      BleConnectionState.permissionRequired =>
        ko ? '블루투스 권한이 필요합니다.' : 'Permission required',
      BleConnectionState.unsupported =>
        ko ? '지원되지 않는 스피커입니다.' : 'This speaker is not supported',
      BleConnectionState.connectionLost =>
        ko ? 'TUNAI ONE과의 연결이 끊어졌습니다.' : 'Connection to TUNAI ONE was lost',
      BleConnectionState.reconnecting =>
        ko ? 'TUNAI ONE에 다시 연결하고 있습니다.' : 'Reconnecting to TUNAI ONE',
      _ => ko ? '연결에 실패했습니다.' : 'Connection failed',
    };

class _SafeConnectionMessage extends StatelessWidget {
  final String text;
  const _SafeConnectionMessage({required this.text});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(color: Colors.white70, fontSize: 14));
}

class _ScanFailureGuide extends StatelessWidget {
  final bool ko;
  final VoidCallback onRetry;
  const _ScanFailureGuide({required this.ko, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ko ? '스피커를 찾지 못했습니다' : "Can't find your speaker?",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 16),
        _Tip(
          ko
              ? '스피커 전원이 켜져 있는지 확인해주세요'
              : 'Turn on speaker and check the power cable',
        ),
        _Tip(ko ? '스피커와 더 가까이서 시도해보세요' : 'Move closer to your speaker'),
        _Tip(ko ? '블루투스가 켜져 있는지 확인해주세요' : 'Make sure Bluetooth is enabled'),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '— ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.25),
              fontSize: 13,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 보드 배너 ─────────────────────────────────────────────────────────────────
class _BoardBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  const _BoardBanner({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 공용 버튼 ─────────────────────────────────────────────────────────────────
class _FullWidthButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool filled;
  const _FullWidthButton({
    super.key,
    required this.label,
    this.onTap,
    this.filled = true,
  });

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
          child: const Text(
            '설정 열기',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    ),
  );
}

// ── 측정 장치 표시 ─────────────────────────────────────────────────────────────
class _InputSourceSection extends StatelessWidget {
  final bool ko;
  final bool isConnected;
  const _InputSourceSection({required this.ko, required this.isConnected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ko ? '측정 장치' : 'Measurement Device',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.35),
            fontSize: 11,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
                color:
                    Colors.white.withValues(alpha: isConnected ? 0.2 : 0.07)),
            borderRadius: BorderRadius.circular(6),
            color: isConnected
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
          ),
          child: Row(children: [
            Icon(
              Icons.smartphone,
              color: isConnected ? Colors.white70 : Colors.white24,
              size: 16,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isConnected
                    ? (ko ? '✓ 스마트폰 마이크' : '✓ Smartphone microphone')
                    : (ko
                        ? '스피커를 연결하면 측정 장치를 확인할 수 있습니다.'
                        : 'Connect your speaker to view measurement device.'),
                style: TextStyle(
                  color: isConnected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.28),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }
}
