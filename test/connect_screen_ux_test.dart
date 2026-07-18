import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/features/ble/ble_controller.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/icp5_consumer_frame_codec.dart';
import 'package:tunai/features/ble/known_consumer_device.dart';
import 'package:tunai/features/connect/connect_screen.dart';

// ── Fakes (mirrors consumer_ble_service_test.dart pattern) ───────────────────

class _NativeHandle {
  final String id;
  const _NativeHandle(this.id);
}

List<int> _identity(String profile) {
  final frame = <int>[
    0x55, 0x18, 0xe0, 0, 0, 0, 0, 0,
    ...ascii.encode(profile),
  ];
  return [...frame, Icp5ConsumerFrameCodec.checksum(frame)];
}

final _validIdentity = _identity('DSP1701.100.00.01');

class _FakeConnection implements ConsumerBleConnection {
  final _ctrl = StreamController<List<int>>.broadcast(sync: true);
  int _writes = 0;
  @override Stream<List<int>> get notifications => _ctrl.stream;
  @override Future<void> write(List<int> bytes) async {
    _writes++;
    if (_writes == 1) _ctrl.add(_validIdentity);
  }
  @override Future<void> close() async {
    if (!_ctrl.isClosed) await _ctrl.close();
  }
}

class _IdleDriver implements ConsumerBleGattDriver {
  @override Future<bool> isBluetoothAvailable() async => true;
  @override Future<bool> requestPermissions() async => true;
  @override Future<List<ConsumerBleDevice>> scan({String? identifier}) async => [];
  @override Future<ConsumerBleConnection> connect(ConsumerBleDevice d) =>
      throw UnimplementedError();
}

class _ConnectedDriver implements ConsumerBleGattDriver {
  @override Future<bool> isBluetoothAvailable() async => true;
  @override Future<bool> requestPermissions() async => true;
  @override Future<List<ConsumerBleDevice>> scan({String? identifier}) async =>
      [const ConsumerBleDevice(
        identifier: 'dev-1',
        name: 'WONDOM ICP5',
        rssi: -42,
        nativeHandle: _NativeHandle('dev-1'),
      )];
  @override Future<ConsumerBleConnection> connect(ConsumerBleDevice d) async =>
      _FakeConnection();
}

class _TestKnownDeviceStore implements KnownConsumerDevicePersistence {
  KnownConsumerDevice? _value;
  @override Future<KnownConsumerDevice?> load() async => _value;
  @override Future<void> save(KnownConsumerDevice d) async => _value = d;
  @override Future<void> clear() async => _value = null;
}

ConsumerBleService _service(ConsumerBleGattDriver driver) =>
    ConsumerBleService(
      driver: driver,
      knownDeviceStore: _TestKnownDeviceStore(),
      handshakeTimeout: const Duration(milliseconds: 40),
      staleAckQuarantine: const Duration(milliseconds: 5),
      reconnectDelays: const [Duration(seconds: 1)],
    );

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko', 'KR')],
      home: child,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Only one primary CTA before connection ────────────────────────────────

  group('Single primary CTA before connection', () {
    testWidgets('EN: exactly one primary scan CTA visible (idle state)',
        (tester) async {
      final service = _service(_IdleDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(
        find.byKey(const Key('consumer_ble_scan_button')),
        findsOneWidget,
      );
      // No secondary filled button with the same label
      expect(find.text('Connect Speaker'), findsWidgets);
      // No duplicate scan button
      expect(
        find.byKey(const Key('consumer_start_room_button')),
        findsNothing,
      );
      service.dispose();
    });

    testWidgets('KO: 스피커 연결하기 is the only primary CTA label', (tester) async {
      final service = _service(_IdleDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {}),
            locale: const Locale('ko', 'KR')),
      ));
      await tester.pump();

      expect(find.text('스피커 연결하기'), findsOneWidget);
      expect(
        find.byKey(const Key('consumer_ble_scan_button')),
        findsOneWidget,
      );
      service.dispose();
    });
  });

  // ── Informational card has no tappable button ─────────────────────────────

  group('Informational card — no tappable button inside', () {
    testWidgets('Card is visible with informational text only', (tester) async {
      final service = _service(_IdleDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(
        find.byKey(const Key('consumer_connect_info_card')),
        findsOneWidget,
      );
      expect(
        find.text('Connect your TUNAI speaker.'),
        findsOneWidget,
      );
      expect(
        find.text('Space analysis becomes available after connection.'),
        findsOneWidget,
      );
      service.dispose();
    });

    testWidgets('KO: card shows Korean informational copy', (tester) async {
      final service = _service(_IdleDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {}),
            locale: const Locale('ko', 'KR')),
      ));
      await tester.pump();

      expect(find.text('TUNAI 스피커를 연결해주세요.'), findsOneWidget);
      expect(
        find.text('스피커를 연결하면 공간 분석을 시작할 수 있습니다.'),
        findsOneWidget,
      );
      service.dispose();
    });
  });

  // ── Step rows are non-interactive ─────────────────────────────────────────

  group('Step rows — non-interactive progress indicators', () {
    testWidgets('Step labels present, no step-row GestureDetectors',
        (tester) async {
      final service = _service(_IdleDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      // Labels visible
      expect(find.text('Connect Speaker'), findsWidgets);
      expect(find.text('Space Analysis'), findsOneWidget);

      // No "STEP 1" / "STEP 2" button-badge text
      expect(find.text('STEP 1'), findsNothing);
      expect(find.text('STEP 2'), findsNothing);

      // Number of GestureDetectors ≤ 2 (only the bottom CTA; no step taps)
      final gds = tester
          .widgetList<GestureDetector>(find.byType(GestureDetector))
          .length;
      expect(gds, lessThanOrEqualTo(2));
      service.dispose();
    });
  });

  // ── CTA changes after connection ──────────────────────────────────────────

  group('CTA changes from Connect Speaker to Analyze Your Space after connection',
      () {
    testWidgets('EN: after connection, CTA becomes Analyze Your Space',
        (tester) async {
      var measureRequested = false;
      final service = _service(_ConnectedDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(
          ConnectScreen(onConnected: () => measureRequested = true),
        ),
      ));

      // Idle state → Connect Speaker CTA
      await tester.pump();
      expect(
          find.byKey(const Key('consumer_ble_scan_button')), findsOneWidget);
      expect(find.text('Connect Speaker'), findsWidgets);

      // Scan → device appears → connect
      await tester.tap(find.byKey(const Key('consumer_ble_scan_button')));
      await tester.pump();
      expect(find.byKey(const Key('consumer_ble_connect_button')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('consumer_ble_connect_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      // Connected state → Analyze Your Space CTA
      expect(find.text('Connected ✓'), findsOneWidget);
      expect(
        find.byKey(const Key('consumer_start_room_button')),
        findsOneWidget,
      );
      expect(find.text('Analyze Your Space'), findsOneWidget);
      // Connect Speaker CTA gone
      expect(
          find.byKey(const Key('consumer_ble_scan_button')), findsNothing);

      await tester.tap(find.byKey(const Key('consumer_start_room_button')));
      expect(measureRequested, isTrue);
      service.dispose();
    });

    testWidgets('KO: after connection, CTA becomes 공간 분석하기', (tester) async {
      final service = _service(_ConnectedDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {}),
            locale: const Locale('ko', 'KR')),
      ));

      await tester.pump();
      await tester.tap(find.byKey(const Key('consumer_ble_scan_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('consumer_ble_connect_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('공간 분석하기'), findsOneWidget);
      expect(find.byKey(const Key('consumer_start_room_button')), findsOneWidget);
      expect(find.byKey(const Key('consumer_ble_scan_button')), findsNothing);
      service.dispose();
    });
  });

  // ── No duplicate connect action ───────────────────────────────────────────

  group('No duplicate connect action rendered', () {
    testWidgets('Before connection: no consumer_start_room_button',
        (tester) async {
      final service = _service(_IdleDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(
          find.byKey(const Key('consumer_start_room_button')), findsNothing);
      service.dispose();
    });

    testWidgets('After connection: only one primary filled CTA visible',
        (tester) async {
      final service = _service(_ConnectedDriver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();
      await tester.tap(find.byKey(const Key('consumer_ble_scan_button')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('consumer_ble_connect_button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(
          find.byKey(const Key('consumer_start_room_button')), findsOneWidget);
      expect(find.text('Analyze Your Space'), findsOneWidget);
      // No scan button (would be a duplicate action)
      expect(
          find.byKey(const Key('consumer_ble_scan_button')), findsNothing);
      service.dispose();
    });
  });
}
