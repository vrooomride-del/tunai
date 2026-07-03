import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../dsp/dsp_compiler.dart';
import '../../core/profiles/system_profile.dart';

// ICP5(WONDOM) BLE GATT UUID — GATT 덤프로 확인된 실제 값
class TunaiUUID {
  static const String service      = 'fff0';
  static const String dspWrite     = 'fff2'; // WRITE|WRITE_NO_RSP
  static const String statusNotify = 'fff1'; // READ|NOTIFY
}

enum BleConnectionState { disconnected, scanning, connecting, connected, error, bluetoothOff }

/// 연결 후 보드 자동탐지 결과
enum DetectedBoard {
  icp5Adau1701, // ICP5 + fff0 서비스 확인 → ADAU1701(JAB4)
  adau1466,     // 파란보드 패턴 → ADAU1466 (아직 미지원)
  unknown,      // 식별 불가 → 수동 선택 유지
}

class BleState {
  final BleConnectionState connection;
  final String? deviceName;
  final String message;
  final bool isSending;
  final DetectedBoard? detectedBoard;

  const BleState({
    this.connection = BleConnectionState.disconnected,
    this.deviceName,
    this.message = '',
    this.isSending = false,
    this.detectedBoard,
  });

  BleState copyWith({
    BleConnectionState? connection,
    String? deviceName,
    String? message,
    bool? isSending,
    DetectedBoard? detectedBoard,
  }) => BleState(
    connection: connection ?? this.connection,
    deviceName: deviceName ?? this.deviceName,
    message: message ?? this.message,
    isSending: isSending ?? this.isSending,
    detectedBoard: detectedBoard ?? this.detectedBoard,
  );
}

final bleProvider = StateNotifierProvider<BleController, BleState>(
  (ref) => BleController(ref),
);

class BleController extends StateNotifier<BleState> {
  final Ref _ref;
  BleController(this._ref) : super(const BleState());

  BluetoothDevice? _device;
  BluetoothCharacteristic? _dspWriteChar;

  // ICP5(WONDOM) BLE 광고 이름 후보 — Miumax에서 보이는 실제 이름으로 업데이트 필요
  static const List<String> _targetNames = ['ICP5', 'icp5', 'TUNAI', 'tunai', 'BT_AUDIO', 'WONDOM'];

  // 파란보드(ADAU1466) advName 패턴 — QCC5125 Bluetooth 이름
  static const List<String> _adau1466Names = ['REFERENCE', 'TUNAI-REF', 'QCC5125', 'CS42448'];

  /// Android 12+ BLE 런타임 권한 요청
  Future<bool> _requestBlePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  /// 스캔 → TUNAI/ICP5 기기 자동 연결
  Future<void> scanAndConnect() async {
    state = state.copyWith(
      connection: BleConnectionState.scanning,
      message: 'TUNAI 스피커 검색 중...',
    );

    // ── Bluetooth 어댑터 상태 확인 ────────────────────────────────
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      state = state.copyWith(
        connection: BleConnectionState.bluetoothOff,
        message: '블루투스가 꺼져 있습니다. 설정에서 켜주세요.',
      );
      return;
    }
    // ─────────────────────────────────────────────────────────────

    final granted = await _requestBlePermissions();
    if (!granted) {
      state = state.copyWith(
        connection: BleConnectionState.error,
        message: 'Bluetooth 권한이 필요합니다.\n설정 > 앱 > TUNAI > 권한에서 허용하세요.',
      );
      return;
    }

    try {
      // withServices 필터 제거: ICP5는 커스텀 ESP32 서비스 UUID를 advertise하지 않음
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

      // scanResults는 BehaviorSubject라 스캔이 끝나도 닫히지 않으므로
      // isScanning이 false가 되면 직접 break 해야 함
      BluetoothDevice? found;
      await for (final results in FlutterBluePlus.scanResults) {
        for (final r in results) {
          final name = r.device.advName;
          if (_targetNames.any((n) => name.contains(n))) {
            found = r.device;
            break;
          }
        }
        if (found != null) break;
        if (!FlutterBluePlus.isScanningNow) break;
      }

      await FlutterBluePlus.stopScan();

      if (found != null) {
        await _connectToDevice(found);
      } else {
        state = state.copyWith(
          connection: BleConnectionState.error,
          message: 'TUNAI/ICP5 스피커를 찾을 수 없습니다.\nMiumax에서 보이는 BLE 이름을 확인하세요.',
        );
      }
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
      // flutter_blue_plus의 connect(timeout:)이 일부 기기/OS 조합에서 제대로
      // 발동하지 않아 SCANNING/연결 중 상태로 무한 대기하는 사례가 있었음 —
      // Dart 레벨에서 강제 타임아웃을 걸어 반드시 error 상태로 복구되게 함.
      await device
          .connect(timeout: const Duration(seconds: 10))
          .timeout(const Duration(seconds: 12), onTimeout: () {
        throw TimeoutException('연결 타임아웃 (12초) — 기기 전원/거리를 확인하세요.');
      });
      _device = device;

      // 서비스 검색 + 디버그 덤프 (여기도 무한 대기 방지)
      final services = await device.discoverServices().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('서비스 검색 타임아웃 (10초)'),
      );

      // ── DEBUG: ICP5 실제 GATT 구조 출력 ──────────────────────────────
      debugPrint('══════════════════════════════════════════');
      debugPrint('GATT dump for ${device.advName} (${device.remoteId})');
      for (final s in services) {
        debugPrint('  SERVICE: ${s.uuid}');
        for (final c in s.characteristics) {
          final props = [
            if (c.properties.read) 'READ',
            if (c.properties.write) 'WRITE',
            if (c.properties.writeWithoutResponse) 'WRITE_NO_RSP',
            if (c.properties.notify) 'NOTIFY',
            if (c.properties.indicate) 'INDICATE',
          ].join('|');
          debugPrint('    CHAR: ${c.uuid}  [$props]');
        }
      }
      debugPrint('══════════════════════════════════════════');
      // ─────────────────────────────────────────────────────────────────

      for (final s in services) {
        // 16비트 short UUID는 128비트로 확장되므로 str 포함 여부로 비교
        if (s.uuid.str128.contains(TunaiUUID.service)) {
          for (final c in s.characteristics) {
            if (c.uuid.str128.contains(TunaiUUID.dspWrite)) {
              _dspWriteChar = c;
            }
          }
        }
      }

      if (_dspWriteChar == null) {
        // 찾지 못한 경우: 실제 UUID를 에러 메시지에 포함
        final summary = services.map((s) =>
          '${s.uuid}: [${s.characteristics.map((c) => c.uuid).join(', ')}]'
        ).join('\n');
        throw Exception(
          'DSP Write 캐릭터리스틱을 찾을 수 없습니다.\n'
          '기대: service=${TunaiUUID.service}\n'
          '실제 서비스:\n$summary',
        );
      }

      // ── 보드 자동탐지 ────────────────────────────────────────────────────
      final board = _detectBoard(device.advName, services);
      debugPrint('[BOARD] 탐지 결과: $board (advName=${device.advName})');

      String connMsg;
      switch (board) {
        case DetectedBoard.icp5Adau1701:
          // ADAU1701 확정 → systemProfile 자동 선택
          _ref.read(systemProfileProvider.notifier).state = kTunaiOneSystemProfile;
          connMsg = '연결됨: ${device.advName} · ADAU1701 자동 선택됨';
        case DetectedBoard.adau1466:
          // ADAU1466 탐지 — 아직 미지원, 프로파일은 건드리지 않음
          connMsg = '연결됨: ${device.advName} · ADAU1466 (지원 준비 중)';
        case DetectedBoard.unknown:
          connMsg = '연결됨: ${device.advName} · 보드 미식별 — 수동 선택 필요';
      }
      // ──────────────────────────────────────────────────────────────────────

      state = state.copyWith(
        connection: BleConnectionState.connected,
        message: connMsg,
        detectedBoard: board,
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
      debugPrint('BLE _connectToDevice ERROR: $e');
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
        debugPrint('[BLE] 패킷 ${i+1}/${packets.length} — ${frame.length}바이트: ${frame.map((b) => b.toRadixString(16).padLeft(2,'0')).join(' ')}');

        await _dspWriteChar!.write(
          frame,
          withoutResponse: false, // ACK 대기
        );
        debugPrint('[BLE] 패킷 ${i+1} 전송 완료 (ACK OK)');

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

  /// advName + GATT 서비스 UUID로 보드 종류를 추정
  ///
  /// ICP5(WONDOM) 탑재 JAB4: advName에 ICP5/WONDOM/TUNAI 포함 + fff0 서비스 존재
  /// 파란보드(ADAU1466): advName에 REFERENCE/QCC5125 등 포함
  /// 그 외: unknown → 수동 선택 유지
  DetectedBoard _detectBoard(String advName, List<BluetoothService> services) {
    final name = advName.toUpperCase();
    final hasFff0 = services.any((s) => s.uuid.str128.contains(TunaiUUID.service));

    // ICP5 패턴: 이름 매칭 AND fff0 서비스 존재 (둘 다 확인)
    final isIcp5Name = _targetNames.any((n) => name.contains(n.toUpperCase()));
    if (isIcp5Name && hasFff0) return DetectedBoard.icp5Adau1701;

    // fff0 없이 이름만 맞는 경우도 ADAU1701로 추정 (ICP5 펌웨어에 따라 UUID 다를 수 있음)
    if (isIcp5Name) return DetectedBoard.icp5Adau1701;

    // 파란보드 패턴
    if (_adau1466Names.any((n) => name.contains(n.toUpperCase()))) {
      return DetectedBoard.adau1466;
    }

    return DetectedBoard.unknown;
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _dspWriteChar = null;
    state = state.copyWith(detectedBoard: null);
  }

  @override
  void dispose() {
    _device?.disconnect();
    super.dispose();
  }
}
