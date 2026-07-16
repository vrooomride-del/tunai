import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profiles/system_profile.dart';
import '../dsp/dsp_compiler.dart';
import 'consumer_ble_service.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  found,
  connecting,
  connected,
  notFound,
  error,
  bluetoothOff,
  permissionRequired,
  unsupported,
}

enum DetectedBoard { icp5Adau1701, adau1466, unknown }

class BleState {
  final BleConnectionState connection;
  final String? deviceName;
  final String message;
  final bool isSending;
  final DetectedBoard? detectedBoard;
  final List<ConsumerBleDevice> devices;
  final String? selectedDeviceIdentifier;

  const BleState({
    this.connection = BleConnectionState.disconnected,
    this.deviceName,
    this.message = '',
    this.isSending = false,
    this.detectedBoard,
    this.devices = const [],
    this.selectedDeviceIdentifier,
  });

  BleState copyWith({
    BleConnectionState? connection,
    String? deviceName,
    String? message,
    bool? isSending,
    DetectedBoard? detectedBoard,
    List<ConsumerBleDevice>? devices,
    String? selectedDeviceIdentifier,
    bool clearConnectionIdentity = false,
    bool clearSelection = false,
  }) => BleState(
    connection: connection ?? this.connection,
    deviceName:
        clearConnectionIdentity ? null : (deviceName ?? this.deviceName),
    message: message ?? this.message,
    isSending: isSending ?? this.isSending,
    detectedBoard:
        clearConnectionIdentity ? null : (detectedBoard ?? this.detectedBoard),
    devices: devices ?? this.devices,
    selectedDeviceIdentifier:
        clearSelection
            ? null
            : (selectedDeviceIdentifier ?? this.selectedDeviceIdentifier),
  );
}

final consumerBleServiceProvider = Provider<ConsumerBleService>((ref) {
  final service = ConsumerBleService();
  ref.onDispose(service.dispose);
  return service;
});

final bleProvider = StateNotifierProvider<BleController, BleState>(
  (ref) => BleController(ref),
);

class BleController extends StateNotifier<BleState> {
  final Ref _ref;
  late final ConsumerBleService _service;

  BleController(this._ref) : super(const BleState()) {
    _service = _ref.read(consumerBleServiceProvider);
    _service.addListener(_onServiceChanged);
  }

  Future<void> scan() => _service.scan();

  /// Kept for callers from the previous CONNECT flow. It now scans only;
  /// connection always requires explicit selection and user action.
  Future<void> scanAndConnect() => scan();

  bool selectDevice(String identifier) => _service.selectDevice(identifier);

  Future<void> connectSelected() => _service.connect();

  void _onServiceChanged() {
    final next = _service.state;
    final connection = switch (next.status) {
      ConsumerBleStatus.disconnected => BleConnectionState.disconnected,
      ConsumerBleStatus.bluetoothUnavailable => BleConnectionState.bluetoothOff,
      ConsumerBleStatus.permissionRequired =>
        BleConnectionState.permissionRequired,
      ConsumerBleStatus.searching => BleConnectionState.scanning,
      ConsumerBleStatus.deviceFound => BleConnectionState.found,
      ConsumerBleStatus.connecting => BleConnectionState.connecting,
      ConsumerBleStatus.connected => BleConnectionState.connected,
      ConsumerBleStatus.connectionFailed =>
        next.devices.isEmpty
            ? BleConnectionState.notFound
            : BleConnectionState.error,
      ConsumerBleStatus.unsupportedDevice => BleConnectionState.unsupported,
    };
    if (next.connected) {
      _ref.read(systemProfileProvider.notifier).state = kTunaiOneSystemProfile;
    }
    state = state.copyWith(
      connection: connection,
      deviceName: next.connected ? next.connectedDeviceName : null,
      detectedBoard: next.connected ? DetectedBoard.icp5Adau1701 : null,
      devices: next.devices,
      selectedDeviceIdentifier: next.selectedDevice?.identifier,
      message: _safeStatus(next.status),
      clearConnectionIdentity: !next.connected,
      clearSelection: next.selectedDevice == null,
    );
  }

  String _safeStatus(ConsumerBleStatus status) => switch (status) {
    ConsumerBleStatus.disconnected => 'Disconnected',
    ConsumerBleStatus.bluetoothUnavailable => 'Bluetooth unavailable',
    ConsumerBleStatus.permissionRequired => 'Permission required',
    ConsumerBleStatus.searching => 'Searching',
    ConsumerBleStatus.deviceFound => 'Device found',
    ConsumerBleStatus.connecting => 'Connecting',
    ConsumerBleStatus.connected => 'Connected',
    ConsumerBleStatus.connectionFailed => 'Connection failed',
    ConsumerBleStatus.unsupportedDevice => 'Unsupported device',
  };

  Future<void> sendRawFrame(Uint8List frame) async {
    await _service.sendApplicationFrame(frame);
  }

  Future<bool> sendPackets(List<RegisterPacket> packets) async {
    if (state.connection != BleConnectionState.connected) {
      state = state.copyWith(message: 'Disconnected');
      return false;
    }
    state = state.copyWith(isSending: true);
    try {
      for (final packet in packets) {
        await _service.sendApplicationFrame(DspCompiler.buildBleFrame(packet));
      }
      state = state.copyWith(isSending: false);
      return true;
    } catch (_) {
      state = state.copyWith(isSending: false, message: 'Connection failed');
      return false;
    }
  }

  Future<void> disconnect() => _service.disconnect();

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
