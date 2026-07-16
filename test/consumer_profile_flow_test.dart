import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/features/ai/ai_screen.dart';
import 'package:tunai/features/ble/ble_controller.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/icp5_consumer_frame_codec.dart';
import 'package:tunai/features/connect/connect_screen.dart';
import 'package:tunai/features/listen/listen_screen.dart';
import 'package:tunai/features/measure/measure_screen.dart';
import 'package:tunai/features/more/about_tunai_screen.dart';
import 'package:tunai/features/more/more_screen.dart';
import 'package:tunai/features/onboarding/onboarding_screen.dart';
import 'package:tunai/main.dart' show currentTabIndexProvider;

final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: kDefaultResultCards,
);
final _created = DateTime.fromMillisecondsSinceEpoch(1000);

void _noop() {}

ConsumerSoundProfile _profile({String id = 'tune-1'}) => ConsumerSoundProfile(
      id: id,
      name: 'Living Room Acoustic Tune',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: _scan.cards,
      profileType: ConsumerProfileType.tunaiTune,
    );

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko')],
      home: child,
    );

class _Connection implements ConsumerBleConnection {
  final _notifications = StreamController<List<int>>.broadcast(sync: true);

  @override
  Stream<List<int>> get notifications => _notifications.stream;

  @override
  Future<void> write(List<int> bytes) async {
    final identity = <int>[
      0x55,
      0x18,
      0xe0,
      0,
      0,
      0,
      0,
      0,
      ...'DSP1701.100.00.01'.codeUnits,
    ];
    _notifications
        .add([...identity, Icp5ConsumerFrameCodec.checksum(identity)]);
  }

  @override
  Future<void> close() => _notifications.close();
}

class _Driver implements ConsumerBleGattDriver {
  final device = const ConsumerBleDevice(
    identifier: 'icp5',
    name: 'WONDOM ICP5 with a deliberately long device name',
    rssi: -68,
    nativeHandle: 'fake',
  );

  @override
  Future<bool> isBluetoothAvailable() async => true;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<List<ConsumerBleDevice>> scan() async => [device];
  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) async =>
      _Connection();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('completed Acoustic Tune is upserted, active, and persisted', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.upsertAndActivate(_profile());
    await notifier.upsertAndActivate(_profile(id: 'tune-2'));

    expect(notifier.state, hasLength(1));
    expect(notifier.state.single.isActive, isTrue);
    expect(notifier.state.single.status, ConsumerProfileStatus.active);
    expect(notifier.state.single.profileType, ConsumerProfileType.tunaiTune);
    expect(notifier.state.single.resultCards, _scan.cards);

    final recreated = ConsumerSoundProfileNotifier();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(recreated.state.single.isActive, isTrue);
    expect(recreated.state.single.roomType, _scan.roomType);
  });

  test('active profile survives tab changes and BLE remains connected',
      () async {
    final service = ConsumerBleService(driver: _Driver());
    final container = ProviderContainer(overrides: [
      consumerBleServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    container.read(bleProvider);
    await service.scan();
    await service.connect();
    expect(
        container.read(bleProvider).connection, BleConnectionState.connected);

    await container
        .read(consumerSoundProfileProvider.notifier)
        .upsertAndActivate(_profile());
    for (final tab in [3, 4, 2, 3]) {
      container.read(currentTabIndexProvider.notifier).state = tab;
      expect(container.read(activeConsumerProfileProvider)?.id, 'tune-1');
      expect(
          container.read(bleProvider).connection, BleConnectionState.connected);
    }
  });

  testWidgets('LISTEN immediately renders the active Consumer profile',
      (tester) async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.upsertAndActivate(_profile());
    await tester.pumpWidget(ProviderScope(
      overrides: [
        consumerSoundProfileProvider.overrideWith((ref) => notifier),
        currentTabIndexProvider.overrideWith((ref) => 3),
      ],
      child: _app(const ListenScreen()),
    ));
    await tester.pump();

    expect(find.text('Living Room Acoustic Tune'), findsWidgets);
    expect(find.text('No Sound Profile applied.'), findsNothing);
  });

  testWidgets('abandoned Tune generation does not create a profile',
      (tester) async {
    final notifier = ConsumerSoundProfileNotifier();
    final scanNotifier = RoomScanResultNotifier();
    await scanNotifier.saveResult(_scan);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        consumerSoundProfileProvider.overrideWith((ref) => notifier),
        roomScanResultProvider.overrideWith((ref) => scanNotifier),
      ],
      child: _app(AiScreen(onApplied: () {})),
    ));
    await tester.tap(find.text('Create Acoustic Tune'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tunai_consumer_sound_profiles'), isNull);
  });

  testWidgets('original onboarding and About TUNAI planning are restored',
      (tester) async {
    await tester.pumpWidget(_app(OnboardingScreen(onComplete: () {})));
    expect(find.text('The audio paradigm is changing.'), findsOneWidget);
    expect(
      find.text(
        'For too long,\nwe listened to sound locked inside the speaker.\n\nTUNAI opens that sound again\nfor your space and your taste.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Your speaker already has its sound.'),
        findsNothing);

    await tester.pumpWidget(_app(const AboutTunaiScreen()));
    expect(find.text('About TUNAI'), findsOneWidget);
    expect(find.text('TUNAI opens that sound again.'), findsOneWidget);
    expect(find.textContaining('factory-tuned sound'), findsNothing);
  });

  testWidgets('original MORE navigation and approved entries are restored',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MoreScreen())),
    );
    await tester.pump();
    expect(find.text('COMMUNITY'), findsOneWidget);
    expect(find.text('TUNAI PRO'), findsOneWidget);
    expect(find.text('PROFILE LIBRARY'), findsOneWidget);
    expect(find.text('FINE TUNE'), findsOneWidget);
    expect(find.text('ABOUT TUNAI'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('FACTORY MODE'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('FACTORY MODE'), findsOneWidget);
  });

  testWidgets('original ROOM and TUNE copy is restored', (tester) async {
    await tester.pumpWidget(
      ProviderScope(child: _app(const MeasureScreen(onMeasured: _noop))),
    );
    expect(
        find.text(
            'Sit where you usually listen.\nKeep the room quiet for a moment.'),
        findsOneWidget);
    expect(
        find.textContaining(
            'Place your phone at your normal listening position.'),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());

    final scanNotifier = RoomScanResultNotifier();
    await scanNotifier.saveResult(_scan);
    await tester.pumpWidget(ProviderScope(
      overrides: [roomScanResultProvider.overrideWith((ref) => scanNotifier)],
      child: _app(AiScreen(onApplied: () {})),
    ));
    expect(
      find.text(
        'TUNAI creates a safe, room-matched Sound Profile.\nNo complex settings — just better sound.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('factory-tuned character'), findsNothing);
  });

  for (final locale in const [Locale('en'), Locale('ko')]) {
    testWidgets(
        'narrow device selector has no overflow (${locale.languageCode})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = ConsumerBleService(driver: _Driver());
      await tester.pumpWidget(ProviderScope(
        overrides: [consumerBleServiceProvider.overrideWithValue(service)],
        child: _app(
          ConnectScreen(onConnected: () {}),
          locale: locale,
        ),
      ));
      await service.scan();
      await tester.pump();
      expect(find.byKey(const Key('consumer_ble_device_selector')),
          findsOneWidget);
      expect(find.text('Nearby speaker'), findsOneWidget);
      expect(find.textContaining('WONDOM'), findsNothing);
      expect(find.textContaining('dBm'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'narrow phone-mic card has no overflow (${locale.languageCode})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_app(
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConsumerMicStrategySection(
              ko: locale.languageCode == 'ko',
            ),
          ),
        ),
        locale: locale,
      ));
      expect(find.text(locale.languageCode == 'ko' ? '사용 중' : 'Active'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
