import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/ble/ble_controller.dart';
import '../core/spectrum_snapshot.dart';
import '../core/ai_tuning_service.dart';

enum FirstRunState {
  noDeviceConnected,
  deviceConnectedNoRoomScan,
  roomScanCompleteNoTune,
  acousticTuneReadyNotApplied,
  acousticTuneApplied,
}

/// Apply 성공 후 수동으로 true로 설정 — BLE/측정 로직 변경 없이 UI 안내만 제어
final acousticTuneAppliedProvider = StateProvider<bool>((ref) => false);

/// 현재 퍼스트런 단계를 기존 데이터 상태(BLE·측정·AI)에서 파생 계산
final firstRunStateProvider = Provider<FirstRunState>((ref) {
  if (ref.watch(acousticTuneAppliedProvider)) {
    return FirstRunState.acousticTuneApplied;
  }
  final ble = ref.watch(bleProvider);
  if (ble.connection != BleConnectionState.connected) {
    return FirstRunState.noDeviceConnected;
  }
  final snap = ref.watch(spectrumSnapshotProvider);
  if (snap.before == null) return FirstRunState.deviceConnectedNoRoomScan;

  final aiResult = ref.watch(lastAiResultProvider);
  if (aiResult == null) return FirstRunState.roomScanCompleteNoTune;

  return FirstRunState.acousticTuneReadyNotApplied;
});
