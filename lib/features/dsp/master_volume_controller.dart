import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/dsp/dsp_address_map.dart';
import '../../core/dsp/transport/dsp_transport_provider.dart';
import '../../core/dsp/transport/dsp_write_logger.dart';
import '../ble/ble_controller.dart';

final masterVolumeProvider =
    StateNotifierProvider<MasterVolumeController, double>(
  (ref) => MasterVolumeController(ref),
);

class MasterVolumeController extends StateNotifier<double> {
  MasterVolumeController(this._ref) : super(-60.0) {
    // BLE 연결 성공 시 자동 -60dB write
    _sub = _ref.listen<BleState>(bleProvider, (prev, next) {
      if (next.connection == BleConnectionState.connected &&
          prev?.connection != BleConnectionState.connected) {
        writeConnectDefault();
      }
    });
  }

  final Ref _ref;
  late final ProviderSubscription<BleState> _sub;

  Future<void> setVolume(double dB) async {
    final clamped = dB.clamp(-70.0, 0.0);
    state = clamped;

    final transport = _ref.read(dspTransportProvider);
    if (transport == null) return;

    // Mobile은 항상 ADAU1701 (BLE ICP5 경유)
    final linear = pow(10.0, clamped / 20.0).toDouble();
    final fixed = (linear * (1 << 23)).round(); // 5.23
    final bytes4 = _toBytes4(fixed);

    await transport.writeParameter(kAdau1701MasterVolL, bytes4);
    await transport.writeParameter(kAdau1701MasterVolR, bytes4);

    _ref.read(dspWriteLoggerProvider).log(
      profile: 'adau1701', param: 'masterVol',
      addrL: kAdau1701MasterVolL, addrR: kAdau1701MasterVolR,
      bytes: bytes4, dB: clamped,
      success: true, timestamp: DateTime.now(),
    );
    debugPrint('[MasterVol] ADAU1701 dB=$clamped');
  }

  Future<void> writeConnectDefault() => setVolume(-60.0);

  /// 슬라이더 드래그 중 UI만 업데이트 (DSP write 없음) — onChangeEnd에서 setVolume 호출.
  void updateUiOnly(double dB) => state = dB.clamp(-70.0, 0.0);

  static List<int> _toBytes4(int v) => [
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ];

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
