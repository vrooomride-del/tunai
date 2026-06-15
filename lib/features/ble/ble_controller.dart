import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dsp/dsp_compiler.dart';

// TUNAI BLE 서비스/캐릭터리스틱 UUID
// ESP32 펌웨어와 반드시 일치해야 함
class TunaiUUID {
  static const String service       = '12345678-1234-1234-1234-123456789ABC';
  static const String dspWrite      = '12345678-1234-1234-1234-123456789ABD'; // Write
  static const String statusNotify  = '12345678-1234-1234-1234-123456789ABE'; // Notify
}

enum BleConnectionState { disconnected, scanning, connecting, connected, error }

class BleState {
  final BleConnectionState connection;
  final String? deviceName;
  final String message;
  final bool isSending;

  const BleState({
    this.connection = BleConnectionState.disconnected,
    this.deviceName,
    this.message = '',
    this.isSending = false,
  });

  BleState copyWith({
    BleConnectionState? connection,
    String? deviceName,
    String? message,
    bool? isSending,
  }) => BleState(
    connection: connection ?? this.connection,
    deviceName: deviceName ?? this.deviceName,
    message: message ?? this.message,
    isSending: isSending ?? this.isSending,
  );
}

final bleProvider = StateNotifierProvider<BleController, BleState>(
  (ref) => BleController(),
);

class BleController extends StateNotifier<BleState> {
  BleController() : super(const BleState());

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dspWriteChar;

  /// 스캔 → TUNAI 기기 자동 연결
  Future<void> scanAndConnect() async {
    state = state.copyWith(
      connection: BleConnectionState.scanning,
      message: 'TUNAI 스피커 검색 중...',
    );

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withServices: [Guid(TunaiUUID.service)],
      );

      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          if (r.device.advName.contains('TUNAI') ||
              r.device.advName.contains('tunai')) {
            await FlutterBluePlus.stopScan();
            await _connectToDevice(r.device);
            return;
          }
        }
      }

      // 10초 내 미발견
      state = state.copyWith(
        connection: BleConnectionState.error,
        message: 'TUNAI 스피커를 찾을 수 없습니다.',
      );
    } catch (e) {
      state = state.copyWith(
        connection: BleConnectionState.error,
        message: '스캔 오류: $e',
      );
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    state = state.copyWith(
      connection: BleConnectionState.connecting,
      message: '${device.advName} 연결 중...',
      deviceName: device.advName,
    );

    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      // 서비스 검색
      final services = await device.discoverServices();
      for (final s in services) {
        if (s.uuid == Guid(TunaiUUID.service)) {
          for (final c in s.characteristics) {
            if (c.uuid == Guid(TunaiUUID.dspWrite)) {
              _dspWriteChar = c;
            }
          }
        }
      }

      if (_dspWriteChar == null) {
        throw Exception('DSP Write 캐릭터리스틱을 찾을 수 없습니다.');
      }

      state = state.copyWith(
        connection: BleConnectionState.connected,
        message: '연결됨: ${device.advName}',
      );

      // 연결 해제 감지
      device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _device = null;
          _dspWriteChar = null;
          state = state.copyWith(
            connection: BleConnectionState.disconnected,
            message: '연결 해제됨',
          );
        }
      });
    } catch (e) {
      state = state.copyWith(
        connection: BleConnectionState.error,
        message: '연결 실패: $e',
      );
    }
  }

  /// DspAdapter가 사용하는 raw BLE 프레임 단일 전송
  Future<void> sendRawFrame(Uint8List frame) async {
    if (_dspWriteChar == null) throw Exception('연결된 기기가 없습니다.');
    await _dspWriteChar!.write(frame, withoutResponse: false);
    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// DSP 패킷 전송 - 27바이트 BLE 프레임
  Future<bool> sendPackets(List<RegisterPacket> packets) async {
    if (_dspWriteChar == null) {
      state = state.copyWith(message: '연결된 기기가 없습니다.');
      return false;
    }

    state = state.copyWith(isSending: true, message: 'DSP 패킷 전송 중...');

    try {
      for (int i = 0; i < packets.length; i++) {
        final frame = DspCompiler.buildBleFrame(packets[i]);

        await _dspWriteChar!.write(
          frame,
          withoutResponse: false, // ACK 대기
        );

        state = state.copyWith(
          message: 'DSP 패킷 전송 중... (${i + 1}/${packets.length})',
        );

        // 패킷 간 간격 (MCU I²C 처리 시간)
        await Future.delayed(const Duration(milliseconds: 50));
      }

      state = state.copyWith(
        isSending: false,
        message: '✓ DSP 적용 완료 (${packets.length}개 필터)',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSending: false,
        message: '전송 실패: $e',
      );
      return false;
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _dspWriteChar = null;
  }

  @override
  void dispose() {
    _device?.disconnect();
    super.dispose();
  }
}
