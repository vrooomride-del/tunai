import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/features/ble/ble_controller.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/icp5_consumer_frame_codec.dart';
import 'package:tunai/features/ble/icp5_peq_command_builder.dart';
import 'package:tunai/features/ble/consumer_product_identity.dart';
import 'package:tunai/features/ble/known_consumer_device.dart';
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

class _TestKnownDeviceStore implements KnownConsumerDevicePersistence {
  KnownConsumerDevice? value;
  @override
  Future<KnownConsumerDevice?> load() async => value;
  @override
  Future<void> save(KnownConsumerDevice device) async => value = device;
  @override
  Future<void> clear() async => value = null;
}

class _FakeConnection implements ConsumerBleConnection {
  final _controller = StreamController<List<int>>.broadcast(sync: true);
  final List<List<int>> writes = [];
  final List<int> identity;
  final bool splitIdentity;
  final bool respond;
  List<int>? applicationResponse;
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
    final response =
        writes.length == 1 ? identity : (applicationResponse ?? identity);
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
  ConsumerBleConnection connection;
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
    ConsumerBleConnection? connection,
    this.connectError,
  }) : connection = connection ?? _FakeConnection();

  @override
  Future<bool> isBluetoothAvailable() async => available;

  @override
  Future<bool> requestPermissions() async => permissions;

  @override
  Future<List<ConsumerBleDevice>> scan({String? identifier}) async {
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
  ConsumerBleGattDriver driver, {
  Duration timeout = const Duration(milliseconds: 40),
  Duration quarantine = const Duration(milliseconds: 5),
  List<Duration>? reconnectDelays,
}) =>
    ConsumerBleService(
      driver: driver,
      knownDeviceStore: _TestKnownDeviceStore(),
      handshakeTimeout: timeout,
      staleAckQuarantine: quarantine,
      reconnectDelays: reconnectDelays ?? const [Duration(seconds: 1)],
    );

// ── Test helpers for stale-ACK and reconnect tests ──────────────────────────

/// A connection whose responses are fully controlled by the caller.
/// write 1 = handshake → responds with [identity]
/// write 2 = application command → responds only if [shouldRespondToApp()] is true
/// write 3+ = responds immediately with peqAck
class _ControlledConnection implements ConsumerBleConnection {
  final StreamController<List<int>> streamCtrl;
  final bool Function() shouldRespondToApp;
  final List<List<int>> writes;
  final List<int> identity;

  _ControlledConnection({
    required this.streamCtrl,
    required this.shouldRespondToApp,
    required this.writes,
    required this.identity,
  });

  @override
  Stream<List<int>> get notifications => streamCtrl.stream;

  @override
  Future<void> write(List<int> bytes) async {
    writes.add(List.unmodifiable(bytes));
    if (writes.length == 1) {
      streamCtrl.add(identity);
    } else if (writes.length == 2) {
      if (shouldRespondToApp()) streamCtrl.add(Icp5PeqCommandBuilder.peqAck);
      // else: no response → caller times out
    } else {
      streamCtrl.add(Icp5PeqCommandBuilder.peqAck);
    }
  }

  @override
  Future<void> close() async {
    if (!streamCtrl.isClosed) await streamCtrl.close();
  }
}

/// A driver that vends connections from a list in order, for reconnect tests.
class _MultiConnectionDriver implements ConsumerBleGattDriver {
  final List<ConsumerBleDevice> devices;
  final List<ConsumerBleConnection> connections;
  final void Function() onConnect;
  int _index = 0;

  _MultiConnectionDriver({
    required this.devices,
    required this.connections,
    required this.onConnect,
  });

  @override
  Future<bool> isBluetoothAvailable() async => true;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<List<ConsumerBleDevice>> scan({String? identifier}) async => devices;
  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) async {
    onConnect();
    return connections[_index++];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test('Consumer identity confirms TUNAI ONE only after validation', () {
    final candidate = ConsumerProductIdentity.fromPhysicalIdentity(
      physicalDeviceName: 'WONDOM ICP5',
      supportedProfileValidated: false,
    );
    expect(candidate.displayName, 'TUNAI ONE');
    expect(candidate.isConfirmed, isFalse);

    final confirmed = ConsumerProductIdentity.fromPhysicalIdentity(
      physicalDeviceName: 'CH9143BLE2U',
      supportedProfileValidated: true,
    );
    expect(confirmed.displayName, 'TUNAI ONE');
    expect(confirmed.isConfirmed, isTrue);
  });

  test('unknown or unsupported candidates are not falsely branded', () {
    final unknown = ConsumerProductIdentity.fromPhysicalIdentity(
      physicalDeviceName: 'Other speaker',
      supportedProfileValidated: false,
    );
    expect(unknown.displayName, 'Nearby speaker');
    expect(unknown.isHighConfidenceCandidate, isFalse);
    expect(unknown.isConfirmed, isFalse);
  });

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

  test('application write awaits the next complete notification frame',
      () async {
    final connection = _FakeConnection()
      ..applicationResponse = Icp5PeqCommandBuilder.peqAck;
    final device = _device('icp5-1', 'WONDOM ICP5');
    final service = _service(
      _FakeDriver(devices: [device], connection: connection),
    );
    await service.scan();
    await service.connect();

    final response = await service.sendApplicationFrameAndAwaitResponse(
      [0x55, 0x01, 0x56],
      timeout: const Duration(milliseconds: 40),
    );

    expect(service.supportedIdentityValidated, isTrue);
    expect(service.validatedDeviceIdentifier, 'icp5-1');
    expect(response, Icp5PeqCommandBuilder.peqAck);
    await service.disconnect();
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

  test('unexpected disconnect enters bounded reconnecting state', () async {
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
    expect(service.state.status, ConsumerBleStatus.reconnecting);
    expect(driver.connectCalls, 1);
    expect(driver.scanCalls, 1);
    service.dispose();
  });

  test('unexpected disconnect becomes consumer-safe connection-lost state',
      () async {
    final connection = _FakeConnection();
    final driver = _FakeDriver(
      devices: [_device('icp5', 'WONDOM ICP5')],
      connection: connection,
    );
    final service = _service(driver);
    final container = ProviderContainer(overrides: [
      consumerBleServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    container.read(bleProvider);
    await service.scan();
    await service.connect();
    expect(container.read(bleProvider).deviceName, 'TUNAI ONE');

    connection.disconnectUnexpectedly();
    await Future<void>.delayed(Duration.zero);
    expect(container.read(bleProvider).connection,
        BleConnectionState.reconnecting);
    expect(driver.connectCalls, 1);
    expect(driver.scanCalls, 1);
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

    // Step progress indicators (non-interactive circles + labels)
    expect(find.text('Connect Speaker'), findsWidgets); // step label + CTA
    expect(find.text('Space Analysis'), findsOneWidget); // step label only
    // Single primary CTA at bottom
    expect(find.byKey(const Key('consumer_ble_scan_button')), findsOneWidget);
    expect(find.text('Connect Speaker'), findsWidgets);
    // Informational card visible, no card button
    expect(find.byKey(const Key('consumer_connect_info_card')), findsOneWidget);

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
    expect(find.text('TUNAI ONE'), findsOneWidget);
    expect(find.text('Strong signal'), findsOneWidget);
    expect(find.text('WONDOM ICP5'), findsNothing);
    expect(find.text('-42 dBm'), findsNothing);

    await tester.tap(find.byKey(const Key('consumer_ble_connect_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(driver.connectCalls, 1);
    expect(driver.scanCalls, 1);
    expect(find.text('DSP1701.100.00.01'), findsNothing);
    expect(find.text('WONDOM ICP5'), findsNothing);

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Connected ✓'), findsOneWidget);
    expect(find.text('Ready to create your personal sound.'), findsOneWidget);
    expect(roomRequested, isFalse);
    await tester.tap(find.byKey(const Key('consumer_start_room_button')));
    expect(roomRequested, isTrue);
    service.dispose();
  });

  testWidgets('Korean CONNECT copy separates status and action',
      (tester) async {
    final service = _service(_FakeDriver(devices: []));
    await tester.pumpWidget(ProviderScope(
      overrides: [consumerBleServiceProvider.overrideWithValue(service)],
      child: MaterialApp(
        locale: const Locale('ko', 'KR'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ko')],
        home: ConnectScreen(onConnected: () {}),
      ),
    ));
    // Step progress indicators
    expect(find.text('스피커 연결'), findsWidgets); // step label + CTA
    expect(find.text('공간 분석'), findsOneWidget); // step label only
    // Single primary CTA
    expect(find.byKey(const Key('consumer_ble_scan_button')), findsOneWidget);
    expect(find.text('스피커 연결하기'), findsOneWidget);
    // Informational card
    expect(find.byKey(const Key('consumer_connect_info_card')), findsOneWidget);
    service.dispose();
  });

  // ── Stale ACK Protection (Finding 1) ────────────────────────────────────────

  group('application frame extraction diagnostics', () {
    Future<
        ({
          ConsumerBleService service,
          StreamController<List<int>> stream,
        })> connectedService() async {
      final stream = StreamController<List<int>>.broadcast(sync: true);
      final connection = _ControlledConnection(
        streamCtrl: stream,
        shouldRespondToApp: () => false,
        writes: [],
        identity: _validIdentity,
      );
      final service = _service(
        _FakeDriver(
          devices: [_device('d1', 'WONDOM ICP5')],
          connection: connection,
        ),
        quarantine: const Duration(milliseconds: 1),
      );
      await service.scan();
      await service.connect();
      return (service: service, stream: stream);
    }

    Future<ConsumerBleApplicationExchange> awaitPeqAck(
      ConsumerBleService service,
      void Function() notify,
    ) async {
      final pending = service.sendApplicationFrameAndAwaitExchange(
        [0x55, 0x01, 0x56],
        timeout: const Duration(milliseconds: 50),
        frameMatcher: Icp5PeqCommandBuilder.isValidPeqAck,
      );
      await Future<void>.delayed(Duration.zero);
      notify();
      return pending;
    }

    test('complete ACK in one notification is accepted unchanged', () async {
      final test = await connectedService();
      final exchange = await awaitPeqAck(
        test.service,
        () => test.stream.add(Icp5PeqCommandBuilder.peqAck),
      );
      expect(exchange.matchedFrame, Icp5PeqCommandBuilder.peqAck);
      expect(exchange.rawNotifications, [Icp5PeqCommandBuilder.peqAck]);
      test.service.dispose();
    });

    test('ACK split across two notifications is buffered and accepted',
        () async {
      final test = await connectedService();
      const ack = Icp5PeqCommandBuilder.peqAck;
      final exchange = await awaitPeqAck(test.service, () {
        test.stream.add(ack.sublist(0, 4));
        test.stream.add(ack.sublist(4));
      });
      expect(exchange.matchedFrame, ack);
      expect(exchange.rawNotifications, [ack.sublist(0, 4), ack.sublist(4)]);
      test.service.dispose();
    });

    test('two concatenated frames are both extracted from one callback',
        () async {
      final test = await connectedService();
      const status = [0x55, 0x02, 0xe2, 0x39];
      const ack = Icp5PeqCommandBuilder.peqAck;
      final combined = [...status, ...ack];
      final exchange = await awaitPeqAck(
        test.service,
        () => test.stream.add(combined),
      );
      expect(exchange.matchedFrame, ack);
      expect(exchange.rawNotifications, [combined]);
      test.service.dispose();
    });

    test('unrelated status frame is ignored until exact PEQ ACK arrives',
        () async {
      final test = await connectedService();
      const status = [0x55, 0x02, 0xe2, 0x39];
      const ack = Icp5PeqCommandBuilder.peqAck;
      final exchange = await awaitPeqAck(test.service, () {
        test.stream.add(status);
        test.stream.add(ack);
      });
      expect(exchange.matchedFrame, ack);
      expect(exchange.rawNotifications, [status, ack]);
      test.service.dispose();
    });

    test('malformed response is logged but never falsely accepted', () async {
      final test = await connectedService();
      final pending = test.service.sendApplicationFrameAndAwaitExchange(
        [0x55, 0x01, 0x56],
        timeout: const Duration(milliseconds: 5),
        frameMatcher: Icp5PeqCommandBuilder.isValidPeqAck,
      );
      await Future<void>.delayed(Duration.zero);
      const malformed = [0x55, 0x07, 0xe1, 0, 0, 0, 0x18, 0, 0x54];
      test.stream.add(malformed);
      try {
        await pending;
        fail('Malformed ACK must not complete the request.');
      } on ConsumerBleApplicationException catch (error) {
        expect(error.cause, isA<TimeoutException>());
        expect(error.exchange.rawNotifications, [malformed]);
        expect(error.exchange.matchedFrame, isEmpty);
      }
      test.service.dispose();
    });
  });

  group('stale ACK protection', () {
    // A controlled connection where each write can be individually governed.
    // write 1 = handshake (always responds with identity)
    // write 2 = application command (controlled by respondToApp)
    // write 3+ = any further writes respond with peqAck immediately
    late StreamController<List<int>> streamCtrl;
    late bool respondToApp;
    late List<List<int>> writes;

    _ControlledConnection makeControlledConnection() {
      streamCtrl = StreamController<List<int>>.broadcast(sync: true);
      respondToApp = false;
      writes = [];
      return _ControlledConnection(
        streamCtrl: streamCtrl,
        shouldRespondToApp: () => respondToApp,
        writes: writes,
        identity: _validIdentity,
      );
    }

    test('timeout clears active generation; subsequent write gets its own ACK',
        () async {
      final conn = makeControlledConnection();
      final service = _service(
        _FakeDriver(devices: [_device('d1', 'WONDOM ICP5')], connection: conn),
        timeout: const Duration(milliseconds: 100),
        quarantine: const Duration(milliseconds: 10),
      );
      await service.scan();
      await service.connect();

      // Application command — no response → TimeoutException after 5 ms.
      await expectLater(
        service.sendApplicationFrameAndAwaitResponse(
          [0x55, 0x01, 0x56],
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );

      // After quarantine the rollback write must succeed with its own ACK.
      respondToApp = true;
      final result = await service.sendApplicationFrameAndAwaitResponse(
        [0x55, 0x02, 0x57],
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, Icp5PeqCommandBuilder.peqAck);
      expect(writes.length, 3); // handshake + app + rollback
      service.dispose();
    });

    test(
        'notification injected during quarantine is discarded; '
        'rollback awaits its own ACK', () async {
      final conn = makeControlledConnection();
      final service = _service(
        _FakeDriver(devices: [_device('d1', 'WONDOM ICP5')], connection: conn),
        timeout: const Duration(milliseconds: 100),
        quarantine: const Duration(milliseconds: 30),
      );
      await service.scan();
      await service.connect();

      // Start application command (will not get a response).
      final appFuture = service.sendApplicationFrameAndAwaitResponse(
        [0x55, 0x01, 0x56],
        timeout: const Duration(milliseconds: 5),
      );

      // After timeout fires, inject a stale ACK while still in quarantine.
      await Future<void>.delayed(const Duration(milliseconds: 8));
      streamCtrl.add(Icp5PeqCommandBuilder.peqAck); // stale — must be discarded

      // Application command throws; quarantine ends after ~35 ms total.
      await expectLater(appFuture, throwsA(isA<TimeoutException>()));

      // Rollback write — enable response now.
      respondToApp = true;
      final rollback = await service.sendApplicationFrameAndAwaitResponse(
        [0x55, 0x02, 0x57],
        timeout: const Duration(milliseconds: 50),
      );
      expect(rollback, Icp5PeqCommandBuilder.peqAck);
      // 3 writes: handshake, application, rollback (stale did not count).
      expect(writes.length, 3);
      service.dispose();
    });

    test('timeout leaves no active pending request', () async {
      final conn = makeControlledConnection();
      final service = _service(
        _FakeDriver(devices: [_device('d1', 'WONDOM ICP5')], connection: conn),
        timeout: const Duration(milliseconds: 100),
        quarantine: const Duration(milliseconds: 10),
      );
      await service.scan();
      await service.connect();

      await expectLater(
        service.sendApplicationFrameAndAwaitResponse(
          [0x55, 0x01, 0x56],
          timeout: const Duration(milliseconds: 5),
        ),
        throwsA(isA<TimeoutException>()),
      );

      // No pending request: a notification now must not throw or hang.
      streamCtrl.add(Icp5PeqCommandBuilder.peqAck);
      await Future<void>.delayed(Duration.zero);
      // If we reach here without exception the test passes.
      service.dispose();
    });
  });

  // ── Disconnect Subscription Cleanup (Finding 2) ──────────────────────────────

  group('disconnect subscription cleanup', () {
    test('reconnect has exactly one notification listener', () async {
      final conn1 = _FakeConnection();
      final conn2 = _FakeConnection()
        ..applicationResponse = Icp5PeqCommandBuilder.peqAck;
      int connectCalls = 0;
      final driver = _MultiConnectionDriver(
        devices: [_device('d1', 'WONDOM ICP5')],
        connections: [conn1, conn2],
        onConnect: () => connectCalls++,
      );
      final service = _service(driver, reconnectDelays: const [Duration.zero]);

      await service.scan();
      await service.connect();
      expect(service.state.status, ConsumerBleStatus.connected);

      // Simulate unexpected disconnect.
      conn1.disconnectUnexpectedly();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.state.status, ConsumerBleStatus.connected);
      expect(connectCalls, 2);

      // A single notification must be processed exactly once.
      conn2.applicationResponse = Icp5PeqCommandBuilder.peqAck;
      final result = await service.sendApplicationFrameAndAwaitResponse(
        [0x55, 0x01, 0x56],
        timeout: const Duration(milliseconds: 50),
      );
      expect(result, Icp5PeqCommandBuilder.peqAck);
      service.dispose();
    });

    test(
        'unexpected disconnect completes pending application request with error',
        () async {
      // Connection that passes handshake but does not respond to application writes.
      final streamCtrl = StreamController<List<int>>.broadcast(sync: true);
      bool respondToApp = false;
      final writes = <List<int>>[];
      final conn = _ControlledConnection(
        streamCtrl: streamCtrl,
        shouldRespondToApp: () => respondToApp,
        writes: writes,
        identity: _validIdentity,
      );
      final service = _service(
        _FakeDriver(devices: [_device('d1', 'WONDOM ICP5')], connection: conn),
      );
      await service.scan();
      await service.connect();
      expect(service.state.status, ConsumerBleStatus.connected);

      final pending = service.sendApplicationFrameAndAwaitResponse(
        [0x55, 0x01, 0x56],
        timeout: const Duration(seconds: 5),
      );
      await Future<void>.delayed(Duration.zero); // let write start

      streamCtrl.addError(StateError('disconnected'));
      await expectLater(pending, throwsStateError);
      service.dispose();
    });
  });

  // ── Handshake Completer Cleanup (Finding 3) ──────────────────────────────────

  group('handshake Completer cleanup', () {
    test(
        'disconnect during handshake fails immediately, not after handshakeTimeout',
        () async {
      // Connection never responds to the handshake write.
      final conn = _FakeConnection(respond: false);
      final service = ConsumerBleService(
        driver: _FakeDriver(
          devices: [_device('d1', 'WONDOM ICP5')],
          connection: conn,
        ),
        handshakeTimeout: const Duration(seconds: 30), // very long
        staleAckQuarantine: const Duration(milliseconds: 5),
      );
      await service.scan();

      // Start connect (will block in handshake).
      final connectFuture = service.connect();

      // Let the connection start, then disconnect immediately.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      conn.disconnectUnexpectedly();

      // connect() must resolve well before the 30 s handshakeTimeout.
      final sw = Stopwatch()..start();
      await connectFuture;
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(
        service.state.status,
        anyOf(
            ConsumerBleStatus.connectionFailed, ConsumerBleStatus.disconnected),
      );
      service.dispose();
    });
  });
}
