import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'icp5_consumer_frame_codec.dart';
import 'consumer_product_identity.dart';
import 'known_consumer_device.dart';

enum ConsumerBleStatus {
  disconnected,
  bluetoothUnavailable,
  permissionRequired,
  searching,
  reconnecting,
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
      status == ConsumerBleStatus.reconnecting ||
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
  Future<List<ConsumerBleDevice>> scan({String? identifier});
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device);
}

@immutable
class ConsumerBleApplicationExchange {
  final List<int> matchedFrame;
  final List<List<int>> rawNotifications;
  final List<int> rawNotificationElapsedMilliseconds;
  final bool gattWriteCompleted;
  final int elapsedMilliseconds;

  const ConsumerBleApplicationExchange({
    required this.matchedFrame,
    required this.rawNotifications,
    required this.rawNotificationElapsedMilliseconds,
    required this.gattWriteCompleted,
    required this.elapsedMilliseconds,
  });
}

class ConsumerBleApplicationException implements Exception {
  final Object cause;
  final ConsumerBleApplicationExchange exchange;

  const ConsumerBleApplicationException(this.cause, this.exchange);

  @override
  String toString() => cause.toString();
}

/// Consumer-safe connection facade for the capture-proven ICP5 BLE channel.
///
/// UUIDs, frames, profile text, and raw notifications remain below this API.
/// The UI can only scan, select, connect, disconnect, and observe safe states.
class ConsumerBleService extends ChangeNotifier {
  final ConsumerBleGattDriver _driver;
  final KnownConsumerDevicePersistence _knownDeviceStore;
  final Duration handshakeTimeout;
  final List<Duration> reconnectDelays;

  /// How long to discard incoming notifications after a command timeout before
  /// allowing the next request. The ICP5 protocol carries no per-command
  /// sequence identifier, so this is a bounded fail-closed mitigation rather
  /// than cryptographic command correlation. The window must exceed the maximum
  /// expected BLE round-trip delay (~30 ms on most stacks).
  final Duration staleAckQuarantine;

  ConsumerBleState _state = const ConsumerBleState();
  ConsumerBleConnection? _connection;
  StreamSubscription<List<int>>? _notificationSubscription;
  Completer<List<int>>? _handshakeResponse;
  Completer<List<int>>? _applicationResponse;
  bool _supportedIdentityValidated = false;
  final List<int> _receiveBuffer = [];

  // Monotonically increasing request generation. A notification is only routed
  // to _applicationResponse when _activeGeneration matches _applicationGeneration.
  // Set to -1 when no request is active or during the stale-ACK quarantine.
  int _applicationGeneration = 0;
  int _activeGeneration = -1;
  bool Function(List<int>)? _applicationFrameMatcher;
  List<List<int>>? _applicationRawNotifications;
  List<int>? _applicationRawNotificationElapsedMilliseconds;
  Stopwatch? _applicationStopwatch;
  bool _applicationWriteCompleted = false;
  bool _initialized = false;
  bool _manualDisconnect = false;
  bool _reconnectLoopActive = false;
  bool _disposed = false;
  int _reconnectGeneration = 0;
  KnownConsumerDevice? _knownDevice;
  Timer? _reconnectDelayTimer;
  Completer<void>? _reconnectDelayCompleter;

  ConsumerBleService({
    ConsumerBleGattDriver? driver,
    KnownConsumerDevicePersistence? knownDeviceStore,
    this.handshakeTimeout = const Duration(seconds: 10),
    this.staleAckQuarantine = const Duration(milliseconds: 50),
    this.reconnectDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
  })  : _driver = driver ?? FlutterBluePlusConsumerGattDriver(),
        _knownDeviceStore = knownDeviceStore ?? KnownConsumerDeviceStore();

  ConsumerBleState get state => _state;
  bool get supportedIdentityValidated =>
      _state.connected && _supportedIdentityValidated;
  String? get validatedDeviceIdentifier =>
      supportedIdentityValidated ? _state.selectedDevice?.identifier : null;
  KnownConsumerDevice? get knownDevice => _knownDevice;
  bool get reconnecting => _reconnectLoopActive;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _knownDevice = await _knownDeviceStore.load();
    final known = _knownDevice;
    if (known != null &&
        known.autoReconnectEnabled &&
        !known.lastDisconnectWasUserInitiated) {
      await _startReconnect(immediate: true);
    }
  }

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
      await _connectAndValidate(selected, reconnecting: false);
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

  Future<void> _connectAndValidate(
    ConsumerBleDevice selected, {
    required bool reconnecting,
  }) async {
    final connection = await _driver.connect(selected);
    _connection = connection;
    _receiveBuffer.clear();
    _handshakeResponse = Completer<List<int>>();
    await _notificationSubscription?.cancel();
    _notificationSubscription = connection.notifications.listen(
      _onNotification,
      onError: _onConnectionError,
      onDone: _onConnectionClosed,
    );
    await connection.write(Icp5ConsumerFrameCodec.identificationRequest);
    debugPrint('[TUNAI BLE] HANDSHAKE_SENT, awaiting fff1 '
        '(timeout=${handshakeTimeout.inSeconds}s)');
    final identity = await _handshakeResponse!.future.timeout(
      handshakeTimeout,
      onTimeout: () {
        debugPrint('[TUNAI BLE] HANDSHAKE_TIMEOUT (no fff1 within '
            '${handshakeTimeout.inSeconds}s)');
        throw TimeoutException('handshake', handshakeTimeout);
      },
    );
    debugPrint('[TUNAI BLE] HANDSHAKE_RECEIVED bytes=${identity.length}');
    if (!Icp5ConsumerFrameCodec.isSupportedIdentity(identity)) {
      await _closeConnection();
      await _blockAutomaticReconnect();
      _setState(ConsumerBleState(
        status: ConsumerBleStatus.unsupportedDevice,
        devices: _state.devices,
        selectedDevice: selected,
      ));
      throw StateError('Unsupported Bluetooth identity.');
    }
    _supportedIdentityValidated = true;
    _handshakeResponse = null;
    _manualDisconnect = false;
    final previous = _knownDevice;
    final known = KnownConsumerDevice(
      identifier: selected.identifier,
      advertisedName: selected.name,
      validatedProductIdentity: ConsumerProductIdentity.tunaiOneDisplayName,
      lastSuccessfulConnectionAt: DateTime.now().toUtc(),
      autoReconnectEnabled: previous?.autoReconnectEnabled ?? true,
      lastDisconnectWasUserInitiated: false,
    );
    try {
      await _knownDeviceStore.save(known);
    } catch (_) {
      // A validated live connection remains usable if local persistence is
      // temporarily unavailable. The next validated connection retries save.
    }
    _knownDevice = known;
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.connected,
      devices: _state.devices,
      selectedDevice: selected,
      connectedDeviceName: selected.name,
    ));
  }

  Future<void> _blockAutomaticReconnect() async {
    final known = _knownDevice;
    if (known == null) return;
    _knownDevice = known.copyWith(autoReconnectEnabled: false);
    try {
      await _knownDeviceStore.save(_knownDevice!);
    } catch (_) {}
  }

  Future<void> _startReconnect({required bool immediate}) async {
    if (_reconnectLoopActive || _state.connected || _disposed) return;
    final known = _knownDevice;
    if (known == null ||
        !known.autoReconnectEnabled ||
        known.lastDisconnectWasUserInitiated) {
      return;
    }
    _reconnectLoopActive = true;
    final generation = ++_reconnectGeneration;
    _setState(ConsumerBleState(
      status: ConsumerBleStatus.reconnecting,
      devices: _state.devices,
      selectedDevice: _state.selectedDevice,
    ));
    try {
      for (var attempt = 0; attempt < reconnectDelays.length; attempt++) {
        if (!_isReconnectCurrent(generation)) return;
        if (!immediate || attempt > 0) {
          await _waitForReconnectDelay(reconnectDelays[attempt]);
        }
        if (!_isReconnectCurrent(generation)) return;
        if (!await _driver.isBluetoothAvailable()) {
          _setState(const ConsumerBleState(
            status: ConsumerBleStatus.bluetoothUnavailable,
          ));
          return;
        }
        if (!await _driver.requestPermissions()) {
          _setState(const ConsumerBleState(
            status: ConsumerBleStatus.permissionRequired,
          ));
          return;
        }
        try {
          final matches = await _driver.scan(identifier: known.identifier);
          final exact = matches
              .where((device) => device.identifier == known.identifier)
              .firstOrNull;
          if (exact == null) continue;
          _setState(ConsumerBleState(
            status: ConsumerBleStatus.reconnecting,
            devices: [exact],
            selectedDevice: exact,
          ));
          await _connectAndValidate(exact, reconnecting: true);
          return;
        } catch (_) {
          await _closeConnection();
          if (_state.status == ConsumerBleStatus.unsupportedDevice) return;
        }
      }
      if (_isReconnectCurrent(generation)) {
        _setState(ConsumerBleState(
          status: ConsumerBleStatus.disconnected,
          devices: _state.devices,
          selectedDevice: _state.selectedDevice,
        ));
      }
    } finally {
      if (generation == _reconnectGeneration) _reconnectLoopActive = false;
    }
  }

  bool _isReconnectCurrent(int generation) =>
      !_disposed && !_manualDisconnect && generation == _reconnectGeneration;

  Future<void> _waitForReconnectDelay(Duration delay) {
    _cancelReconnectDelay();
    final completer = Completer<void>();
    _reconnectDelayCompleter = completer;
    _reconnectDelayTimer = Timer(delay, () {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void _cancelReconnectDelay() {
    _reconnectDelayTimer?.cancel();
    _reconnectDelayTimer = null;
    final completer = _reconnectDelayCompleter;
    _reconnectDelayCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> sendApplicationFrame(List<int> bytes) async {
    if (!_state.connected || _connection == null) {
      throw StateError('Bluetooth device is not connected.');
    }
    await _connection!.write(bytes);
  }

  /// Writes one application frame and returns the next complete notification.
  /// Only one request may be awaiting a response at a time.
  ///
  /// On timeout the generation is invalidated immediately and a bounded
  /// stale-ACK quarantine drains any delayed notification from the timed-out
  /// command before the caller can issue a rollback write. See
  /// [staleAckQuarantine] for the rationale.
  Future<List<int>> sendApplicationFrameAndAwaitResponse(
    List<int> bytes, {
    required Duration timeout,
  }) async {
    try {
      return (await sendApplicationFrameAndAwaitExchange(
        bytes,
        timeout: timeout,
        frameMatcher: (_) => true,
      ))
          .matchedFrame;
    } on ConsumerBleApplicationException catch (error, stackTrace) {
      Error.throwWithStackTrace(error.cause, stackTrace);
    }
  }

  /// Records every raw notification callback, extracts all complete length-
  /// framed messages, and completes only when [frameMatcher] accepts a frame.
  Future<ConsumerBleApplicationExchange> sendApplicationFrameAndAwaitExchange(
    List<int> bytes, {
    required Duration timeout,
    required bool Function(List<int>) frameMatcher,
  }) async {
    if (!_state.connected ||
        _connection == null ||
        !_supportedIdentityValidated) {
      throw StateError('Bluetooth device is not connected and validated.');
    }
    if (_applicationResponse != null) {
      throw StateError('Another Bluetooth command is awaiting a response.');
    }
    final generation = ++_applicationGeneration;
    _activeGeneration = generation;
    _applicationFrameMatcher = frameMatcher;
    _applicationRawNotifications = <List<int>>[];
    _applicationRawNotificationElapsedMilliseconds = <int>[];
    _applicationStopwatch = Stopwatch()..start();
    _applicationWriteCompleted = false;
    final response = Completer<List<int>>();
    _applicationResponse = response;
    try {
      // Subscribe (Completer set above) before write — never after.
      await _connection!.write(bytes);
      _applicationWriteCompleted = true;
      final frame = await response.future.timeout(timeout);
      return _currentApplicationExchange(frame);
    } on TimeoutException catch (error) {
      final exchange = _currentApplicationExchange(const []);
      // Invalidate the generation first so any in-flight notification is
      // discarded immediately, then quarantine to absorb delayed BLE frames
      // that arrive before the caller can issue a rollback write.
      _clearApplicationRequest(generation, response);
      await Future<void>.delayed(staleAckQuarantine);
      _receiveBuffer.clear();
      throw ConsumerBleApplicationException(error, exchange);
    } catch (error) {
      if (error is ConsumerBleApplicationException) rethrow;
      throw ConsumerBleApplicationException(
        error,
        _currentApplicationExchange(const []),
      );
    } finally {
      _clearApplicationRequest(generation, response);
    }
  }

  ConsumerBleApplicationExchange _currentApplicationExchange(
    List<int> matchedFrame,
  ) =>
      ConsumerBleApplicationExchange(
        matchedFrame: List.unmodifiable(matchedFrame),
        rawNotifications: List.unmodifiable([
          for (final notification in _applicationRawNotifications ?? const [])
            List<int>.unmodifiable(notification),
        ]),
        rawNotificationElapsedMilliseconds: List.unmodifiable(
          _applicationRawNotificationElapsedMilliseconds ?? const [],
        ),
        gattWriteCompleted: _applicationWriteCompleted,
        elapsedMilliseconds: _applicationStopwatch?.elapsedMilliseconds ?? 0,
      );

  void _clearApplicationRequest(int generation, Completer<List<int>> response) {
    if (_activeGeneration == generation) _activeGeneration = -1;
    if (_applicationGeneration == generation &&
        (_applicationResponse == null ||
            identical(_applicationResponse, response))) {
      _applicationResponse = null;
      _applicationFrameMatcher = null;
      _applicationRawNotifications = null;
      _applicationRawNotificationElapsedMilliseconds = null;
      _applicationStopwatch?.stop();
      _applicationStopwatch = null;
      _applicationWriteCompleted = false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _reconnectLoopActive = false;
    _reconnectGeneration++;
    _cancelReconnectDelay();
    final known = _knownDevice;
    if (known != null) {
      _knownDevice = known.copyWith(lastDisconnectWasUserInitiated: true);
      try {
        await _knownDeviceStore.save(_knownDevice!);
      } catch (_) {}
    }
    await _closeConnection();
    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.disconnected,
        devices: _state.devices,
        selectedDevice: _state.selectedDevice,
      ),
    );
  }

  Future<void> forgetDevice() async {
    _manualDisconnect = true;
    _reconnectLoopActive = false;
    _reconnectGeneration++;
    _cancelReconnectDelay();
    await _closeConnection();
    await _knownDeviceStore.clear();
    _knownDevice = null;
    _setState(const ConsumerBleState(status: ConsumerBleStatus.disconnected));
  }

  Future<void> setAutoReconnectEnabled(bool enabled) async {
    final known = _knownDevice;
    if (known == null) return;
    _knownDevice = known.copyWith(
      autoReconnectEnabled: enabled,
      lastDisconnectWasUserInitiated:
          enabled ? false : known.lastDisconnectWasUserInitiated,
    );
    await _knownDeviceStore.save(_knownDevice!);
    if (enabled && !_state.connected) await _startReconnect(immediate: true);
  }

  void _onNotification(List<int> bytes) {
    if (_activeGeneration >= 0 && _applicationResponse != null) {
      _applicationRawNotifications?.add(List<int>.unmodifiable(bytes));
      _applicationRawNotificationElapsedMilliseconds
          ?.add(_applicationStopwatch?.elapsedMilliseconds ?? 0);
    }
    _receiveBuffer.addAll(bytes);
    while (true) {
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
        continue;
      }
      // Unrelated complete frames are retained in the raw notification log but
      // cannot satisfy this request. Exact PEQ ACK validation is unchanged.
      final application = _applicationResponse;
      final matcher = _applicationFrameMatcher;
      if (application != null &&
          !application.isCompleted &&
          _activeGeneration >= 0 &&
          matcher != null &&
          matcher(frame)) {
        application.complete(frame);
      }
    }
  }

  void _onConnectionError(Object error, StackTrace stackTrace) {
    debugPrint('[TUNAI BLE] CONN_ERROR handshakePending='
        '${_handshakeResponse != null} connected=${_state.connected} error=$error');
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
    debugPrint('[TUNAI BLE] CONN_CLOSED handshakePending='
        '${_handshakeResponse != null} connected=${_state.connected}');
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
    // Cancel subscription so reconnect does not accumulate a second listener.
    _notificationSubscription?.cancel();
    _notificationSubscription = null;
    // Invalidate any active request generation so in-flight notifications
    // from the old connection are discarded even if delivered asynchronously.
    _activeGeneration = -1;
    final application = _applicationResponse;
    _applicationResponse = null;
    if (application != null && !application.isCompleted) {
      application.completeError(StateError('Bluetooth disconnected.'));
    }
    _connection = null;
    _supportedIdentityValidated = false;
    _setState(
      ConsumerBleState(
        status: ConsumerBleStatus.disconnected,
        devices: _state.devices,
        selectedDevice: _state.selectedDevice,
      ),
    );
    if (!_manualDisconnect) unawaited(_startReconnect(immediate: false));
  }

  Future<void> _closeConnection() async {
    final subscription = _notificationSubscription;
    _notificationSubscription = null;
    await subscription?.cancel();
    final connection = _connection;
    _connection = null;
    _activeGeneration = -1;
    // Complete both pending operations with an error immediately so callers
    // do not stall until their individual timeouts fire.
    final handshake = _handshakeResponse;
    _handshakeResponse = null;
    if (handshake != null && !handshake.isCompleted) {
      handshake.completeError(StateError('Bluetooth disconnected.'));
    }
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
    _disposed = true;
    _reconnectGeneration++;
    _cancelReconnectDelay();
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
  Future<List<ConsumerBleDevice>> scan({String? identifier}) async {
    final byIdentifier = <String, ConsumerBleDevice>{};
    late final StreamSubscription<List<ScanResult>> subscription;
    subscription = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        // NOTE: `advertisementData.connectable` reflects only the packet type of
        // the moment (ADV_IND vs scan-response / non-connectable), so it flaps
        // between true/false as BLE devices alternate advertising packets. It
        // intermittently excludes the ICP5. `connectable` is advisory only; the
        // connect guard still handles unconnectable devices, so list all here.
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
    final devices = byIdentifier.values
        .where(
            (device) => identifier == null || device.identifier == identifier)
        .toList(growable: false);
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
    // Best-effort: clear any stale GATT link the OS/flutter_blue_plus may
    // still be holding for this identifier from a previous app run (killed
    // without a clean disconnect) or a just-failed connect attempt. This is
    // connection-session hygiene only — no protocol bytes, UUIDs, or the
    // handshake/write flow below change. Ignored if there was nothing to
    // clear; this must never block or fail the real connect attempt that
    // follows.
    try {
      await peripheral.disconnect().timeout(const Duration(milliseconds: 800));
    } catch (_) {}
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
      onError: (Object e, StackTrace s) {
        debugPrint('[TUNAI BLE] RX_VALUE_ERROR $e');
        _notifications.addError(e, s);
      },
    );
    _stateSubscription = device.connectionState.listen((state) {
      debugPrint('[TUNAI BLE] DEVICE_STATE_CHANGED state=$state closing=$_closing');
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
