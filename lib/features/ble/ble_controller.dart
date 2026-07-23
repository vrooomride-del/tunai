import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profiles/system_profile.dart';
import '../dsp/dsp_compiler.dart';
import 'consumer_ble_service.dart';
import 'consumer_product_identity.dart';
import 'known_consumer_device.dart';
import '../../core/consumer_sound_profile.dart';

enum BleConnectionState {
  disconnected,
  scanning,
  found,
  connecting,
  reconnecting,
  connected,
  notFound,
  error,
  bluetoothOff,
  permissionRequired,
  unsupported,
  connectionLost,
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
  final bool hasKnownDevice;
  /// Increments every time a NEW connection is established (transition into
  /// [BleConnectionState.connected] from a non-connected state) — never on
  /// simple state churn while already connected. Lets session-scoped facts
  /// tied to "this specific connection" (e.g. audio Speaker Check
  /// confirmation — see speaker_verification_session.dart) distinguish a
  /// continuous connection from a disconnect-and-reconnect to the very same
  /// device identifier, since a physical BLE drop very likely also dropped
  /// the phone's separate Bluetooth AUDIO route even if the app reconnects
  /// to an identical device afterward.
  final int connectionGeneration;

  const BleState({
    this.connection = BleConnectionState.disconnected,
    this.deviceName,
    this.message = '',
    this.isSending = false,
    this.detectedBoard,
    this.devices = const [],
    this.selectedDeviceIdentifier,
    this.hasKnownDevice = false,
    this.connectionGeneration = 0,
  });

  BleState copyWith({
    BleConnectionState? connection,
    String? deviceName,
    String? message,
    bool? isSending,
    DetectedBoard? detectedBoard,
    List<ConsumerBleDevice>? devices,
    String? selectedDeviceIdentifier,
    bool? hasKnownDevice,
    int? connectionGeneration,
    bool clearConnectionIdentity = false,
    bool clearSelection = false,
  }) =>
      BleState(
        connection: connection ?? this.connection,
        deviceName:
            clearConnectionIdentity ? null : (deviceName ?? this.deviceName),
        message: message ?? this.message,
        isSending: isSending ?? this.isSending,
        detectedBoard: clearConnectionIdentity
            ? null
            : (detectedBoard ?? this.detectedBoard),
        devices: devices ?? this.devices,
        selectedDeviceIdentifier: clearSelection
            ? null
            : (selectedDeviceIdentifier ?? this.selectedDeviceIdentifier),
        hasKnownDevice: hasKnownDevice ?? this.hasKnownDevice,
        connectionGeneration: connectionGeneration ?? this.connectionGeneration,
      );
}

final knownConsumerDeviceStoreProvider =
    Provider<KnownConsumerDevicePersistence>((_) => KnownConsumerDeviceStore());

final consumerBleServiceProvider = Provider<ConsumerBleService>((ref) {
  final service = ConsumerBleService(
    knownDeviceStore: ref.read(knownConsumerDeviceStoreProvider),
  );
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
    Future.microtask(() async {
      await _service.initialize();
      _onServiceChanged();
    });
  }

  Future<void> scan() => _service.scan();

  /// Kept for callers from the previous CONNECT flow. It now scans only;
  /// connection always requires explicit selection and user action.
  Future<void> scanAndConnect() => scan();

  bool selectDevice(String identifier) => _service.selectDevice(identifier);

  Future<void> connectSelected() => _service.connect();

  void _onServiceChanged() {
    final next = _service.state;
    final wasConnected = state.connection == BleConnectionState.connected;
    final connection = switch (next.status) {
      ConsumerBleStatus.disconnected => wasConnected
          ? BleConnectionState.connectionLost
          : BleConnectionState.disconnected,
      ConsumerBleStatus.bluetoothUnavailable => BleConnectionState.bluetoothOff,
      ConsumerBleStatus.permissionRequired =>
        BleConnectionState.permissionRequired,
      ConsumerBleStatus.searching => BleConnectionState.scanning,
      ConsumerBleStatus.reconnecting => BleConnectionState.reconnecting,
      ConsumerBleStatus.deviceFound => BleConnectionState.found,
      ConsumerBleStatus.connecting => BleConnectionState.connecting,
      ConsumerBleStatus.connected => BleConnectionState.connected,
      ConsumerBleStatus.connectionFailed => next.devices.isEmpty
          ? BleConnectionState.notFound
          : BleConnectionState.error,
      ConsumerBleStatus.unsupportedDevice => BleConnectionState.unsupported,
    };
    final isFreshConnect =
        next.connected && state.connection != BleConnectionState.connected;
    if (next.connected) {
      _ref.read(systemProfileProvider.notifier).state = kTunaiOneSystemProfile;
    }
    if ((wasConnected && !next.connected) || isFreshConnect) {
      _ref
          .read(consumerSoundProfileProvider.notifier)
          .markCurrentDspConfidenceUnknown();
    }
    state = state.copyWith(
      connection: connection,
      connectionGeneration:
          isFreshConnect ? state.connectionGeneration + 1 : null,
      deviceName: next.connected
          ? ConsumerProductIdentity.fromPhysicalIdentity(
              physicalDeviceName: next.connectedDeviceName ?? '',
              supportedProfileValidated: true,
            ).displayName
          : null,
      detectedBoard: next.connected ? DetectedBoard.icp5Adau1701 : null,
      devices: next.devices,
      selectedDeviceIdentifier: next.selectedDevice?.identifier,
      message: _safeStatus(next.status),
      hasKnownDevice: _service.knownDevice != null,
      clearConnectionIdentity: !next.connected,
      clearSelection: next.selectedDevice == null,
    );
  }

  String _safeStatus(ConsumerBleStatus status) => switch (status) {
        ConsumerBleStatus.disconnected => 'Disconnected',
        ConsumerBleStatus.bluetoothUnavailable => 'Bluetooth unavailable',
        ConsumerBleStatus.permissionRequired => 'Permission required',
        ConsumerBleStatus.searching => 'Searching',
        ConsumerBleStatus.reconnecting => 'Reconnecting',
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

  Future<void> cancelReconnect() => _service.disconnect();

  Future<void> forgetDevice() async {
    await _service.forgetDevice();
    await _ref
        .read(consumerSoundProfileProvider.notifier)
        .markCurrentDspConfidenceUnknown();
  }

  Future<void> setAutoReconnectEnabled(bool enabled) =>
      _service.setAutoReconnectEnabled(enabled);

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
