import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'icp5_consumer_frame_codec.dart';

enum ConsumerBleStatus {
  disconnected,
  bluetoothUnavailable,
  permissionRequired,
  searching,
  deviceFound,
  connecting,
  connected,
  connectionFailed,
  unsupportedDevice,
}

@immutable
class ConsumerBleDevice {
  final String identifier;
  final String name;
  final int? rssi;
  final Object nativeHandle;

  const ConsumerBleDevice({
    required this.identifier,
    required this.name,
    required this.nativeHandle,
    this.rssi,
  });
}

@immutable
class ConsumerBleState {
  final ConsumerBleStatus status;
  final List<ConsumerBleDevice> devices;
  final ConsumerBleDevice? selectedDevice;
  final String? connectedDeviceName;

  const ConsumerBleState({
    this.status = ConsumerBleStatus.disconnected,
    this.devices = const [],
    this.selectedDevice,
    this.connectedDeviceName,
  });

  bool get connected => status == ConsumerBleStatus.connected;
  bool get busy =>
      status == ConsumerBleStatus.searching ||
      status == ConsumerBleStatus.connecting;
}

abstract interface class ConsumerBleConnection {
  Stream<List<int>> get notifications;
  Future<void> write(List<int> bytes);
  Future<void> close();
}

abstract interface class ConsumerBleGattDriver {
  Future<bool> isBluetoothAvailable();
  Future<bool> requestPermissions();
  Future<List<ConsumerBleDevice>> scan();
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device);
}

/// Consumer-safe connection facade for the capture-proven ICP5 BLE channel.
///
/// UUIDs, frames, profile text, and raw notifications remain below this API.
/// The UI can only scan, select, connect, disconnect, and observe safe states.
class ConsumerBleService extends ChangeNotifier {
  final ConsumerBleGattDriver _driver;
  final Duration handshakeTimeout;
  ConsumerBleState _state = const ConsumerBleState();
  ConsumerBleConnection? _connection;
  StreamSubscription<List<int>>? _notificationSubscription;
  Completer<List<int>>? _handshakeResponse;
  Completer<List<int>>? _applicationResponse;
  bool _supportedIdentityValidated = false;
  final List<int> _receiveBuffer = [];

  ConsumerBleService({
    ConsumerBleGattDriver? driver,
    this.handshakeTimeout = const Duration(seconds: 10),
  }) : _driver = driver ?? FlutterBluePlusConsumerGattDriver();

  ConsumerBleState get state => _state;
  bool get supportedIdentityValidated =>
      _state.connected && _supportedIdentityValidated;
  String? get validatedDeviceIdentifier =>
      supportedIdentityValidated ? _state.selectedDevice?.identifier : null;

  Future<void> scan() async {
    if (_state.busy || _state.connected) return;
    if (!await _driver.isBluetoothAvailable()) {
      _setState(
        const ConsumerBleState(status: ConsumerBleStatus.bluetoothUnavailable),
      );
      return;
    }
    if (!await _driver.requestPermissions()) {
      _setState(
        const ConsumerBleState(status: ConsumerBleStatus.permissionRequired),
      );
      return;
    }

    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.searching,
        devices: _state.devices,
        selectedDevice: _state.selectedDevice,
      ),
    );
    try {
      final devices = await _driver.scan();
      final preferred = devices
          .where(
            (device) => device.name.trim().toUpperCase() == 'WONDOM ICP5',
          )
          .firstOrNull;
      _setState(
        ConsumerBleState(
          status: devices.isEmpty
              ? ConsumerBleStatus.connectionFailed
              : ConsumerBleStatus.deviceFound,
          devices: List.unmodifiable(devices),
          selectedDevice: preferred ?? devices.firstOrNull,
        ),
      );
    } on TimeoutException {
      _setState(
        const ConsumerBleState(status: ConsumerBleStatus.connectionFailed),
      );
    } catch (_) {
      _setState(
        const ConsumerBleState(status: ConsumerBleStatus.connectionFailed),
      );
    }
  }

  bool selectDevice(String identifier) {
    if (_state.busy || _state.connected) return false;
    final matches = _state.devices.where(
      (device) => device.identifier == identifier,
    );
    if (matches.length != 1) return false;
    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.deviceFound,
        devices: _state.devices,
        selectedDevice: matches.single,
      ),
    );
    return true;
  }

  Future<void> connect() async {
    if (_state.busy || _state.connected) return;
    final selected = _state.selectedDevice;
    if (selected == null ||
        !_state.devices.any((device) => identical(device, selected))) {
      _setState(
        ConsumerBleState(
          status: ConsumerBleStatus.connectionFailed,
          devices: _state.devices,
        ),
      );
      return;
    }
    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.connecting,
        devices: _state.devices,
        selectedDevice: selected,
      ),
    );

    try {
      final connection = await _driver.connect(selected);
      _connection = connection;
      _receiveBuffer.clear();
      _handshakeResponse = Completer<List<int>>();
      _notificationSubscription = connection.notifications.listen(
        _onNotification,
        onError: _onConnectionError,
        onDone: _onConnectionClosed,
      );
      await connection.write(Icp5ConsumerFrameCodec.identificationRequest);
      final identity = await _handshakeResponse!.future.timeout(
        handshakeTimeout,
      );
      if (!Icp5ConsumerFrameCodec.isSupportedIdentity(identity)) {
        await _closeConnection();
        _setState(
          ConsumerBleState(
            status: ConsumerBleStatus.unsupportedDevice,
            devices: _state.devices,
            selectedDevice: selected,
          ),
        );
        return;
      }
      _supportedIdentityValidated = true;
      _handshakeResponse = null;
      _setState(
        ConsumerBleState(
          status: ConsumerBleStatus.connected,
          devices: _state.devices,
          selectedDevice: selected,
          connectedDeviceName: selected.name,
        ),
      );
    } on TimeoutException {
      await _closeConnection();
      _setState(
        ConsumerBleState(
          status: ConsumerBleStatus.connectionFailed,
          devices: _state.devices,
          selectedDevice: selected,
        ),
      );
    } catch (error) {
      await _closeConnection();
      _setState(
        ConsumerBleState(
          status: error.toString().toLowerCase().contains('unsupported')
              ? ConsumerBleStatus.unsupportedDevice
              : ConsumerBleStatus.connectionFailed,
          devices: _state.devices,
          selectedDevice: selected,
        ),
      );
    }
  }

  Future<void> sendApplicationFrame(List<int> bytes) async {
    if (!_state.connected || _connection == null) {
      throw StateError('Bluetooth device is not connected.');
    }
    await _connection!.write(bytes);
  }

  /// Writes one application frame and returns the next complete notification.
  /// Only one request may be awaiting a response at a time.
  Future<List<int>> sendApplicationFrameAndAwaitResponse(
    List<int> bytes, {
    required Duration timeout,
  }) async {
    if (!_state.connected ||
        _connection == null ||
        !_supportedIdentityValidated) {
      throw StateError('Bluetooth device is not connected and validated.');
    }
    if (_applicationResponse != null) {
      throw StateError('Another Bluetooth command is awaiting a response.');
    }
    final response = Completer<List<int>>();
    _applicationResponse = response;
    try {
      await _connection!.write(bytes);
      return await response.future.timeout(timeout);
    } finally {
      if (identical(_applicationResponse, response)) {
        _applicationResponse = null;
      }
    }
  }

  Future<void> disconnect() async {
    await _closeConnection();
    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.disconnected,
        devices: _state.devices,
        selectedDevice: _state.selectedDevice,
      ),
    );
  }

  void _onNotification(List<int> bytes) {
    _receiveBuffer.addAll(bytes);
    while (_receiveBuffer.isNotEmpty && _receiveBuffer.first != 0x55) {
      _receiveBuffer.removeAt(0);
    }
    if (_receiveBuffer.length < 2) return;
    final frameLength = _receiveBuffer[1] + 2;
    if (_receiveBuffer.length < frameLength) return;
    final frame = List<int>.of(_receiveBuffer.take(frameLength));
    _receiveBuffer.removeRange(0, frameLength);
    final completer = _handshakeResponse;
    if (completer != null && !completer.isCompleted) {
      completer.complete(frame);
      return;
    }
    final application = _applicationResponse;
    if (application != null && !application.isCompleted) {
      application.complete(frame);
    }
  }

  void _onConnectionError(Object error, StackTrace stackTrace) {
    final completer = _handshakeResponse;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error, stackTrace);
      return;
    }
    final application = _applicationResponse;
    if (application != null && !application.isCompleted) {
      application.completeError(error, stackTrace);
    }
    _failClosedAfterDisconnect();
  }

  void _onConnectionClosed() {
    final completer = _handshakeResponse;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(StateError('Bluetooth disconnected.'));
      return;
    }
    final application = _applicationResponse;
    if (application != null && !application.isCompleted) {
      application.completeError(StateError('Bluetooth disconnected.'));
    }
    _failClosedAfterDisconnect();
  }

  void _failClosedAfterDisconnect() {
    if (!_state.connected) return;
    _connection = null;
    _supportedIdentityValidated = false;
    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.disconnected,
        devices: _state.devices,
        selectedDevice: _state.selectedDevice,
      ),
    );
  }

  Future<void> _closeConnection() async {
    final subscription = _notificationSubscription;
    _notificationSubscription = null;
    await subscription?.cancel();
    final connection = _connection;
    _connection = null;
    _handshakeResponse = null;
    final application = _applicationResponse;
    _applicationResponse = null;
    if (application != null && !application.isCompleted) {
      application.completeError(StateError('Bluetooth disconnected.'));
    }
    _supportedIdentityValidated = false;
    _receiveBuffer.clear();
    await connection?.close();
  }

  void _setState(ConsumerBleState next) {
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    _connection?.close();
    super.dispose();
  }
}

class FlutterBluePlusConsumerGattDriver implements ConsumerBleGattDriver {
  static const _serviceUuid = 'fff0';
  static const _txUuid = 'fff2';
  static const _rxUuid = 'fff1';
  final Duration scanTimeout;

  FlutterBluePlusConsumerGattDriver({
    this.scanTimeout = const Duration(seconds: 10),
  });

  @override
  Future<bool> isBluetoothAvailable() async {
    if (kIsWeb) return false;
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  @override
  Future<bool> requestPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final statuses = await <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return statuses.values.every((status) => status.isGranted);
  }

  @override
  Future<List<ConsumerBleDevice>> scan() async {
    final byIdentifier = <String, ConsumerBleDevice>{};
    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        if (!result.advertisementData.connectable) continue;
        final identifier = result.device.remoteId.str;
        final advertised = result.device.advName.trim();
        final platform = result.device.platformName.trim();
        byIdentifier[identifier] = ConsumerBleDevice(
          identifier: identifier,
          name: advertised.isNotEmpty
              ? advertised
              : (platform.isNotEmpty ? platform : 'Bluetooth device'),
          rssi: result.rssi,
          nativeHandle: result.device,
        );
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: scanTimeout);
      await FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .first
          .timeout(scanTimeout + const Duration(seconds: 1));
    } finally {
      await FlutterBluePlus.stopScan();
      await subscription.cancel();
    }
    final devices = byIdentifier.values.toList(growable: false);
    devices.sort((left, right) {
      final leftPreferred = left.name.trim().toUpperCase() == 'WONDOM ICP5';
      final rightPreferred = right.name.trim().toUpperCase() == 'WONDOM ICP5';
      if (leftPreferred != rightPreferred) return leftPreferred ? -1 : 1;
      return (right.rssi ?? -999).compareTo(left.rssi ?? -999);
    });
    return devices;
  }

  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) async {
    final peripheral = device.nativeHandle;
    if (peripheral is! BluetoothDevice ||
        peripheral.remoteId.str != device.identifier) {
      throw StateError('Selected Bluetooth device no longer matches.');
    }
    await peripheral
        .connect(timeout: const Duration(seconds: 10))
        .timeout(const Duration(seconds: 12));
    final services = await peripheral.discoverServices().timeout(
          const Duration(seconds: 10),
        );
    final service = services
        .where((candidate) => matchesExpectedUuid(candidate.uuid, _serviceUuid))
        .firstOrNull;
    if (service == null) {
      await peripheral.disconnect();
      throw StateError('Unsupported Bluetooth device.');
    }
    final tx = service.characteristics
        .where((candidate) => matchesExpectedUuid(candidate.uuid, _txUuid))
        .firstOrNull;
    final rx = service.characteristics
        .where((candidate) => matchesExpectedUuid(candidate.uuid, _rxUuid))
        .firstOrNull;
    if (tx == null ||
        !(tx.properties.write || tx.properties.writeWithoutResponse) ||
        rx == null ||
        !rx.properties.notify) {
      await peripheral.disconnect();
      throw StateError('Unsupported Bluetooth device.');
    }
    await rx.setNotifyValue(true);
    return _FlutterBluePlusConsumerConnection(peripheral, tx, rx);
  }

  @visibleForTesting
  static bool matchesExpectedUuid(Guid uuid, String shortUuid) {
    final short = shortUuid.toLowerCase();
    final full = '0000$short-0000-1000-8000-00805f9b34fb';
    return uuid.str.toLowerCase() == short || uuid.str128.toLowerCase() == full;
  }
}

class _FlutterBluePlusConsumerConnection implements ConsumerBleConnection {
  final BluetoothDevice device;
  final BluetoothCharacteristic tx;
  final BluetoothCharacteristic rx;
  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();
  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _stateSubscription;
  bool _closing = false;

  _FlutterBluePlusConsumerConnection(this.device, this.tx, this.rx) {
    _valueSubscription = rx.onValueReceived.listen(
      (bytes) => _notifications.add(List.unmodifiable(bytes)),
      onError: _notifications.addError,
    );
    _stateSubscription = device.connectionState.listen((state) {
      if (!_closing && state == BluetoothConnectionState.disconnected) {
        _notifications.addError(StateError('Bluetooth disconnected.'));
      }
    });
  }

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<void> write(List<int> bytes) async {
    await tx
        .write(bytes, withoutResponse: false, timeout: 10)
        .timeout(const Duration(seconds: 10));
  }

  @override
  Future<void> close() async {
    if (_closing) return;
    _closing = true;
    await _valueSubscription?.cancel();
    await _stateSubscription?.cancel();
    if (rx.isNotifying) await rx.setNotifyValue(false);
    await device.disconnect();
    await _notifications.close();
  }
}
