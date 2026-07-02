import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../ble/ble_controller.dart';
import '../../shared/widgets.dart';

/// CONNECT 탭 — 스피커 BLE 스캔/연결만 담당.
/// 연결 성공 시 [onConnected]로 MEASURE 탭 자동 전환을 요청한다.
class ConnectScreen extends ConsumerWidget {
  final VoidCallback onConnected;
  const ConnectScreen({super.key, required this.onConnected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bState = ref.watch(bleProvider);

    ref.listen<BleState>(bleProvider, (prev, next) {
      if (next.connection == BleConnectionState.bluetoothOff &&
          prev?.connection != BleConnectionState.bluetoothOff) {
        _showBluetoothOffDialog(context);
      }
      if (next.connection == BleConnectionState.connected &&
          prev?.connection != BleConnectionState.connected) {
        onConnected();
      }
    });

    final isScanning = bState.connection == BleConnectionState.scanning || bState.connection == BleConnectionState.connecting;
    final isConnected = bState.connection == BleConnectionState.connected;

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
                    if (isConnected) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: OutlineButton(label: 'MEASURE로 이동', onTap: onConnected),
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
