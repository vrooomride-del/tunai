import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/icp5_consumer_frame_codec.dart';
import 'package:tunai/features/ble/known_consumer_device.dart';

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

class _MemoryKnownDeviceStore implements KnownConsumerDevicePersistence {
  KnownConsumerDevice? value;
  int saves = 0;
  int clears = 0;

  _MemoryKnownDeviceStore([this.value]);

  @override
  Future<KnownConsumerDevice?> load() async => value;

  @override
  Future<void> save(KnownConsumerDevice device) async {
    saves++;
    value = device;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

class _TestConnection implements ConsumerBleConnection {
  final StreamController<List<int>> controller;
  final List<int> identity;
  int writes = 0;
  int closeCalls = 0;

  _TestConnection({List<int>? identity, void Function()? onListen})
      : identity = identity ?? _validIdentity,
        controller = StreamController<List<int>>.broadcast(
          sync: true,
          onListen: onListen,
        );

  @override
  Stream<List<int>> get notifications => controller.stream;

  @override
  Future<void> write(List<int> bytes) async {
    writes++;
    controller.add(identity);
  }

  void loseConnection() => controller.addError(StateError('link lost'));

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

class _TestDriver implements ConsumerBleGattDriver {
  final List<ConsumerBleDevice> devices;
  final List<Object> connectOutcomes;
  int scanCalls = 0;
  int connectCalls = 0;
  int outcomeIndex = 0;
  final List<String?> scanIdentifiers = [];

  _TestDriver({required this.devices, required this.connectOutcomes});

  @override
  Future<bool> isBluetoothAvailable() async => true;

  @override
  Future<bool> requestPermissions() async => true;

  @override
  Future<List<ConsumerBleDevice>> scan({String? identifier}) async {
    scanCalls++;
    scanIdentifiers.add(identifier);
    return devices
        .where(
            (device) => identifier == null || device.identifier == identifier)
        .toList();
  }

  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) async {
    connectCalls++;
    final outcome = connectOutcomes[outcomeIndex++];
    if (outcome is ConsumerBleConnection) return outcome;
    throw outcome;
  }
}

ConsumerBleDevice _device([String id = 'remembered-id']) => ConsumerBleDevice(
      identifier: id,
      name: 'WONDOM ICP5',
      nativeHandle: Object(),
    );

KnownConsumerDevice _known({
  bool manual = false,
  bool autoReconnect = true,
}) =>
    KnownConsumerDevice(
      identifier: 'remembered-id',
      advertisedName: 'WONDOM ICP5',
      validatedProductIdentity: 'TUNAI ONE',
      lastSuccessfulConnectionAt: DateTime.utc(2026, 7, 17),
      autoReconnectEnabled: autoReconnect,
      lastDisconnectWasUserInitiated: manual,
    );

ConsumerBleService _service(
  _TestDriver driver,
  _MemoryKnownDeviceStore store, {
  List<Duration> delays = const [Duration.zero],
}) =>
    ConsumerBleService(
      driver: driver,
      knownDeviceStore: store,
      handshakeTimeout: const Duration(milliseconds: 30),
      reconnectDelays: delays,
    );

Future<void> _connectManually(ConsumerBleService service) async {
  await service.scan();
  await service.connect();
  expect(service.state.status, ConsumerBleStatus.connected);
}

void main() {
  test('known device is saved only after identity validation', () async {
    final store = _MemoryKnownDeviceStore();
    final invalid = _TestConnection(identity: _identity('DSP1701.100.00.02'));
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [invalid],
    );
    final service = _service(driver, store);

    await service.scan();
    await service.connect();

    expect(service.state.status, ConsumerBleStatus.unsupportedDevice);
    expect(store.value, isNull);
    expect(store.saves, 0);
    service.dispose();
  });

  test('startup reconnects only to remembered identifier', () async {
    final store = _MemoryKnownDeviceStore(_known());
    final driver = _TestDriver(
      devices: [_device('other-id'), _device()],
      connectOutcomes: [_TestConnection()],
    );
    final service = _service(driver, store);

    await service.initialize();

    expect(service.state.status, ConsumerBleStatus.connected);
    expect(service.validatedDeviceIdentifier, 'remembered-id');
    expect(driver.scanIdentifiers, ['remembered-id']);
    expect(store.value!.lastDisconnectWasUserInitiated, isFalse);
    service.dispose();
  });

  test('manual disconnect persists opt-out and restart does not reconnect',
      () async {
    final store = _MemoryKnownDeviceStore();
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [_TestConnection()],
    );
    final service = _service(driver, store);
    await _connectManually(service);
    await service.disconnect();

    final restartDriver =
        _TestDriver(devices: [_device()], connectOutcomes: []);
    final restarted = _service(restartDriver, store);
    await restarted.initialize();

    expect(store.value!.lastDisconnectWasUserInitiated, isTrue);
    expect(restartDriver.scanCalls, 0);
    expect(restarted.state.status, ConsumerBleStatus.disconnected);
    service.dispose();
    restarted.dispose();
  });

  test('unexpected disconnect retries and succeeds after temporary failure',
      () async {
    final store = _MemoryKnownDeviceStore();
    final first = _TestConnection();
    final recovered = _TestConnection();
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [first, StateError('temporary'), recovered],
    );
    final service = _service(
      driver,
      store,
      delays: const [Duration.zero, Duration.zero, Duration.zero],
    );
    final states = <ConsumerBleStatus>[];
    service.addListener(() => states.add(service.state.status));
    await _connectManually(service);

    first.loseConnection();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(states, contains(ConsumerBleStatus.reconnecting));
    expect(service.state.status, ConsumerBleStatus.connected);
    expect(driver.connectCalls, 3);
    expect(recovered.writes, 1); // identity only; no DSP application write
    service.dispose();
  });

  test('unexpected disconnect retry is bounded and stops at maximum', () async {
    final store = _MemoryKnownDeviceStore();
    final first = _TestConnection();
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [
        first,
        StateError('1'),
        StateError('2'),
        StateError('3'),
        StateError('4'),
      ],
    );
    final service = _service(
      driver,
      store,
      delays: List.filled(4, Duration.zero),
    );
    await _connectManually(service);

    first.loseConnection();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(driver.connectCalls, 5);
    expect(service.state.status, ConsumerBleStatus.disconnected);
    expect(service.reconnecting, isFalse);
    service.dispose();
  });

  test('identity mismatch blocks later automatic reconnect', () async {
    final store = _MemoryKnownDeviceStore(_known());
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [
        _TestConnection(identity: _identity('DSP1701.100.00.02')),
      ],
    );
    final service = _service(driver, store);

    await service.initialize();

    expect(service.state.status, ConsumerBleStatus.unsupportedDevice);
    expect(store.value!.autoReconnectEnabled, isFalse);
    service.dispose();
  });

  test('duplicate startup reconnect and notification subscription are single',
      () async {
    var subscriptions = 0;
    final store = _MemoryKnownDeviceStore(_known());
    final connection = _TestConnection(onListen: () => subscriptions++);
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [connection],
    );
    final service = _service(driver, store);

    await Future.wait([service.initialize(), service.initialize()]);

    expect(driver.scanCalls, 1);
    expect(driver.connectCalls, 1);
    expect(subscriptions, 1);
    service.dispose();
  });

  test('Forget Device clears persistence without an application write',
      () async {
    final store = _MemoryKnownDeviceStore();
    final connection = _TestConnection();
    final driver = _TestDriver(
      devices: [_device()],
      connectOutcomes: [connection],
    );
    final service = _service(driver, store);
    await _connectManually(service);

    await service.forgetDevice();

    expect(store.value, isNull);
    expect(store.clears, 1);
    expect(service.state.status, ConsumerBleStatus.disconnected);
    expect(connection.writes, 1); // identity handshake only
    service.dispose();
  });
}
