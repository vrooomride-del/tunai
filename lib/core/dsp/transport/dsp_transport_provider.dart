import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dsp_transport.dart';
import 'adau1701_ble_transport.dart';
import '../../../features/ble/ble_controller.dart';

final dspTransportProvider = Provider<DspTransport?>((ref) {
  final ble = ref.watch(bleProvider);
  if (ble.connection != BleConnectionState.connected) return null;

  final sendFn = ref.read(bleProvider.notifier).sendRawFrame;
  return Adau1701BleTransport(sendFn);
});
