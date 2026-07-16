import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/features/ble/ble_controller.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/icp5_consumer_frame_codec.dart';
import 'package:tunai/features/connect/connect_screen.dart';

List<int> _identity(String profile) {
  final frame = <int>[
    0x55,
    0x18,
    0xe0,
    0,
    0,
    0,
    0,
    0,
    ...ascii.encode(profile),
  ];
  return [...frame, Icp5ConsumerFrameCodec.checksum(frame)];
}

final _validIdentity = _identity('DSP1701.100.00.01');

class _NativeHandle {
  final String id;
  const _NativeHandle(this.id);
}

class _FakeConnection implements ConsumerBleConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  final List<List<int>> writes = [];
  final List<int> identity;
  final bool splitIdentity;
  final bool respond;
  bool notifySubscribed = true;
  int closeCalls = 0;

  _FakeConnection({
    List<int>? identity,
    this.splitIdentity = false,
    this.respond = true,
  }) : identity = identity ?? _validIdentity;

  @override
  Stream<List<int>> get notifications => _controller.stream;

  @override
  Future<void> write(List<int> bytes) async {
    expect(notifySubscribed, isTrue);
    writes.add(List.unmodifiable(bytes));
    if (!respond) return;
    final response = identity;
    if (splitIdentity) {
      _controller.add(response.sublist(0, 7));
      _controller.add(response.sublist(7));
    } else {
      _controller.add(response);
    }
  }

  void disconnectUnexpectedly() {
    _controller.addError(StateError('disconnected'));
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (!_controller.isClosed) await _controller.close();
  }
}

class _FakeDriver implements ConsumerBleGattDriver {
  bool available;
  bool permissions;
  List<ConsumerBleDevice> devices;
  _FakeConnection connection;
  Object? connectError;
  int scanCalls = 0;
  int connectCalls = 0;
  ConsumerBleDevice? connectedDevice;
  bool serviceResolved = false;
  bool txResolved = false;
  bool rxNotifySubscribed = false;

  _FakeDriver({
    this.available = true,
    this.permissions = true,
    required this.devices,
    _FakeConnection? connection,
    this.connectError,
  }) : connection = connection ?? _FakeConnection();

  @override
  Future<bool> isBluetoothAvailable() async => available;

  @override
  Future<bool> requestPermissions() async => permissions;

  @override
  Future<List<ConsumerBleDevice>> scan() async {
    scanCalls++;
    return devices;
  }

  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) async {
    connectCalls++;
    connectedDevice = device;
    if (connectError case final error?) throw error;
    serviceResolved = true;
    txResolved = true;
    rxNotifySubscribed = true;
    return connection;
  }
}

ConsumerBleDevice _device(String id, String name, {int? rssi}) =>
    ConsumerBleDevice(
      identifier: id,
      name: name,
      rssi: rssi,
      nativeHandle: _NativeHandle(id),
    );

ConsumerBleService _service(
  _FakeDriver driver, {
  Duration timeout = const Duration(milliseconds: 40),
}) =>
    ConsumerBleService(driver: driver, handshakeTimeout: timeout);

void main() {
  test('capture-proven handshake request is byte-for-byte unchanged', () {
    expect(Icp5ConsumerFrameCodec.identificationRequest, [
      0x55,
      0x07,
      0x1a,
      0,
      0,
      0,
      0,
      0,
      0x76,
    ]);
    expect(Icp5ConsumerFrameCodec.isSupportedIdentity(_validIdentity), isTrue);
  });

  test('short and Bluetooth Base UUID forms resolve only required GATT IDs',
      () {
    expect(
      FlutterBluePlusConsumerGattDriver.matchesExpectedUuid(
        Guid('fff0'),
        'fff0',
      ),
      isTrue,
    );
    expect(
      FlutterBluePlusConsumerGattDriver.matchesExpectedUuid(
        Guid('0000fff2-0000-1000-8000-00805f9b34fb'),
        'fff2',
      ),
      isTrue,
    );
    expect(
      FlutterBluePlusConsumerGattDriver.matchesExpectedUuid(
        Guid('fff3'),
        'fff1',
      ),
      isFalse,
    );
  });

  test('BLE unavailable fails before permissions or scan', () async {
    final driver = _FakeDriver(available: false, devices: []);
    final service = _service(driver);
    await service.scan();
    expect(service.state.status, ConsumerBleStatus.bluetoothUnavailable);
    expect(driver.scanCalls, 0);
    service.dispose();
  });

  test('permission denial fails before scan', () async {
    final driver = _FakeDriver(permissions: false, devices: []);
    final service = _service(driver);
    await service.scan();
    expect(service.state.status, ConsumerBleStatus.permissionRequired);
    expect(driver.scanCalls, 0);
    service.dispose();
  });

  test('scan exposes state, prefers WONDOM ICP5, and allows manual selection',
      () async {
    final other = _device('other', 'Other speaker', rssi: -30);
    final icp5 = _device('icp5', 'WONDOM ICP5', rssi: -60);
    final driver = _FakeDriver(devices: [other, icp5]);
    final service = _service(driver);
    final statuses = <ConsumerBleStatus>[];
    service.addListener(() => statuses.add(service.state.status));
    await service.scan();
    expect(statuses, contains(ConsumerBleStatus.searching));
    expect(service.state.status, ConsumerBleStatus.deviceFound);
    expect(service.state.selectedDevice, same(icp5));
    expect(service.selectDevice('other'), isTrue);
    expect(service.state.selectedDevice, same(other));
    expect(service.selectDevice('missing'), isFalse);
    service.dispose();
  });

  test('connect preserves exact selection and does not rescan or substitute',
      () async {
    final first = _device('first', 'Other');
    final selected = _device('selected', 'WONDOM ICP5');
    final driver = _FakeDriver(devices: [first, selected]);
    final service = _service(driver);
    await service.scan();
    expect(service.selectDevice('first'), isTrue);
    await service.connect();
    expect(driver.connectedDevice, same(first));
    expect(driver.scanCalls, 1);
    expect(driver.connectCalls, 1);
    expect(service.state.status, ConsumerBleStatus.connected);
    service.dispose();
  });

  test('service/tx/rx resolution precedes exact partial-frame handshake',
      () async {
    final connection = _FakeConnection(splitIdentity: true);
    final driver = _FakeDriver(
      devices: [_device('icp5', 'WONDOM ICP5')],
      connection: connection,
    );
    final service = _service(driver);
    await service.scan();
    await service.connect();
    expect(driver.serviceResolved, isTrue);
    expect(driver.txResolved, isTrue);
    expect(driver.rxNotifySubscribed, isTrue);
    expect(connection.writes, [Icp5ConsumerFrameCodec.identificationRequest]);
    expect(service.state.status, ConsumerBleStatus.connected);
    service.dispose();
  });

  test('wrong profile is rejected as unsupported', () async {
    final driver = _FakeDriver(
      devices: [_device('icp5', 'WONDOM ICP5')],
      connection: _FakeConnection(identity: _identity('DSP1701.100.00.02')),
    );
    final service = _service(driver);
    await service.scan();
    await service.connect();
    expect(service.state.status, ConsumerBleStatus.unsupportedDevice);
    expect(driver.connectCalls, 1);
    service.dispose();
  });

  test('missing required GATT structure is unsupported and has no fallback',
      () async {
    final driver = _FakeDriver(
      devices: [_device('icp5', 'WONDOM ICP5')],
      connectError: StateError('Unsupported Bluetooth device.'),
    );
    final service = _service(driver);
    await service.scan();
    await service.connect();
    expect(service.state.status, ConsumerBleStatus.unsupportedDevice);
    expect(driver.scanCalls, 1);
    expect(driver.connectCalls, 1);
    service.dispose();
  });

  test('handshake timeout fails closed without retry', () async {
    final driver = _FakeDriver(
      devices: [_device('icp5', 'WONDOM ICP5')],
      connection: _FakeConnection(respond: false),
    );
    final service = _service(driver, timeout: const Duration(milliseconds: 5));
    await service.scan();
    await service.connect();
    expect(service.state.status, ConsumerBleStatus.connectionFailed);
    expect(driver.connectCalls, 1);
    expect(driver.scanCalls, 1);
    service.dispose();
  });

  test('disconnect fails closed and never retries', () async {
    final connection = _FakeConnection();
    final driver = _FakeDriver(
      devices: [_device('icp5', 'WONDOM ICP5')],
      connection: connection,
    );
    final service = _service(driver);
    await service.scan();
    await service.connect();
    connection.disconnectUnexpectedly();
    await Future<void>.delayed(Duration.zero);
    expect(service.state.status, ConsumerBleStatus.disconnected);
    expect(driver.connectCalls, 1);
    expect(driver.scanCalls, 1);
    service.dispose();
  });

  testWidgets('Consumer UI is safe and CONNECT can proceed to ROOM',
      (tester) async {
    final driver = _FakeDriver(
      devices: [
        _device('other', 'Other speaker', rssi: -20),
        _device('icp5', 'WONDOM ICP5', rssi: -42),
      ],
    );
    final service = _service(driver);
    var roomRequested = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: MaterialApp(
          home: ConnectScreen(
            onConnected: () => roomRequested = true,
          ),
        ),
      ),
    );

    expect(find.text('PASS_ACK'), findsNothing);
    expect(find.text('PASS_HANDSHAKE'), findsNothing);
    expect(find.text('DSP1701.100.00.01'), findsNothing);
    expect(find.text('FFF0'), findsNothing);
    expect(find.text('FFF1'), findsNothing);
    expect(find.text('FFF2'), findsNothing);
    expect(find.textContaining('Parameter'), findsNothing);

    await tester.tap(find.byKey(const Key('consumer_ble_scan_button')));
    await tester.pump();
    expect(
        find.byKey(const Key('consumer_ble_device_selector')), findsOneWidget);
    expect(find.text('WONDOM ICP5 · -42 dBm'), findsOneWidget);

    await tester.tap(find.byKey(const Key('consumer_ble_connect_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(driver.connectCalls, 1);
    expect(driver.scanCalls, 1);
    expect(find.text('DSP1701.100.00.01'), findsNothing);

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    Navigator.of(tester.element(dialog)).pop(true);
    await tester.pump();
    expect(roomRequested, isTrue);
    service.dispose();
  });
}
