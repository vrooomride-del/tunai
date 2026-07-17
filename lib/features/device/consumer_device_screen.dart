import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ble/ble_controller.dart';
import '../../shared/widgets.dart';

class ConsumerDeviceScreen extends ConsumerWidget {
  const ConsumerDeviceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ko = Localizations.localeOf(context).languageCode == 'ko';
    final state = ref.watch(bleProvider);
    final service = ref.read(consumerBleServiceProvider);
    final known = service.knownDevice;
    final connected = state.connection == BleConnectionState.connected;
    final lastConnected = known == null
        ? (ko ? '기록 없음' : 'Not available')
        : _formatLastConnected(known.lastSuccessfulConnectionAt.toLocal(), ko);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(children: [
          TunaiTopBar(subtitle: ko ? '연결된 스피커' : 'CONNECTED SPEAKER'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              children: [
                Text(known?.validatedProductIdentity ?? 'TUNAI ONE',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w300)),
                const SizedBox(height: 12),
                Text(
                  connected
                      ? (ko ? '연결됨 ✓' : 'Connected ✓')
                      : (ko ? '연결 안 됨' : 'Not connected'),
                  style: TextStyle(
                      color:
                          connected ? const Color(0xFF69F0AE) : Colors.white38,
                      fontSize: 14),
                ),
                const SizedBox(height: 32),
                _InfoRow(
                  label: ko ? '자동 재연결' : 'Auto reconnect',
                  value: known?.autoReconnectEnabled == true ? 'ON' : 'OFF',
                ),
                _InfoRow(
                  label: ko ? '마지막 연결' : 'Last connected',
                  value: lastConnected,
                ),
                const SizedBox(height: 28),
                if (connected)
                  _ActionButton(
                    key: const Key('device_disconnect_button'),
                    label: ko ? '연결 해제' : 'Disconnect',
                    onTap: () => ref.read(bleProvider.notifier).disconnect(),
                  ),
                if (known != null) ...[
                  const SizedBox(height: 10),
                  _ActionButton(
                    key: const Key('device_forget_button'),
                    label: ko ? '기기 지우기' : 'Forget Device',
                    outlined: true,
                    onTap: () => ref.read(bleProvider.notifier).forgetDevice(),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    ko
                        ? '기기 기록만 삭제됩니다. 스피커의 현재 사운드 설정이 초기화되었다고 표시하지 않습니다.'
                        : 'This removes the remembered device only. It does not reset or verify the speaker’s current sound.',
                    style: const TextStyle(
                        color: Colors.white30, fontSize: 11, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

String _formatLastConnected(DateTime value, bool ko) {
  final now = DateTime.now();
  final time = '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  final today = now.year == value.year &&
      now.month == value.month &&
      now.day == value.day;
  if (today) return ko ? '오늘 $time' : 'Today $time';
  return '${value.year}.${value.month.toString().padLeft(2, '0')}.'
      '${value.day.toString().padLeft(2, '0')} $time';
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool outlined;
  const _ActionButton(
      {super.key,
      required this.label,
      required this.onTap,
      this.outlined = false});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: outlined ? Colors.transparent : Colors.white,
            foregroundColor: outlined ? Colors.white70 : Colors.black,
            side: const BorderSide(color: Colors.white24),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      );
}
