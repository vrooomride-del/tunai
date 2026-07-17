import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/tune_plan.dart';
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
  Future<List<ConsumerBleDevice>> scan({String? identifier}) async => [device];
  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) async =>
      _Connection();
}

// ── Deployment persistence helpers ───────────────────────────────────────────

ConsumerDspDeploymentRecord _record({
  required ConsumerDspDeploymentRecordResult result,
  bool dspApplied = false,
}) => ConsumerDspDeploymentRecord(
      tunePlanId: 'plan-1',
      deviceIdentifier: 'device-1',
      attemptedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      bandCount: 1,
      result: result,
      dspApplied: dspApplied,
    );

void _expectStatus(
  ConsumerSoundProfileNotifier notifier,
  String profileId,
  TuneDeploymentStatus expected,
) {
  final profile = notifier.state.firstWhere((p) => p.id == profileId);
  expect(profile.deploymentStatus, expected);
}

ConsumerSoundProfile _profileWithId(String id) => ConsumerSoundProfile(
      id: id,
      name: 'Test Profile $id',
      roomType: 'Living Room',
      createdAt: _created,
      updatedAt: _created,
      micProfileName: 'Generic',
      confidence: 'High',
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: kDefaultResultCards,
    );

// ─────────────────────────────────────────────────────────────────────────────

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
    await tester.tap(find.text('Create Your Sound'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('tunai_consumer_sound_profiles'), isNull);
  });

  testWidgets('release onboarding and About TUNAI copy is present',
      (tester) async {
    await tester.pumpWidget(_app(OnboardingScreen(onComplete: () {})));
    expect(find.text('Your speaker learns your room.'), findsOneWidget);
    expect(
      find.text(
        'Room Analysis listens from where you enjoy music and understands your space.',
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

  testWidgets('release MORE navigation contains consumer entries only',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: MoreScreen())),
    );
    await tester.pump();
    expect(find.text('CONNECTED DEVICE'), findsOneWidget);
    expect(find.text('SOUND PROFILES'), findsOneWidget);
    expect(find.text('HELP & SUPPORT'), findsOneWidget);
    expect(find.text('ABOUT TUNAI'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.textContaining('FACTORY'), findsNothing);
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
        'TUNAI creates a safe, room-matched personal sound.\nNo complex settings — just better sound.',
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

  // ── Deployment persistence truth (Findings 4 & 5) ──────────────────────────

  group('deployment persistence truth', () {

  test('blocked result persists notDeployed', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.add(_profileWithId('p1'));
    await notifier.recordDspDeployment(
      'p1',
      _record(result: ConsumerDspDeploymentRecordResult.blocked),
    );
    _expectStatus(notifier, 'p1', TuneDeploymentStatus.notDeployed);
  });

  test('restored result (rollback succeeded) persists notDeployed', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.add(_profileWithId('p2'));
    await notifier.recordDspDeployment(
      'p2',
      _record(result: ConsumerDspDeploymentRecordResult.restored),
    );
    _expectStatus(notifier, 'p2', TuneDeploymentStatus.notDeployed);
  });

  test('applied result persists applied and preserves history', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.add(_profileWithId('p3'));
    final rec = _record(
      result: ConsumerDspDeploymentRecordResult.applied,
      dspApplied: true,
    );
    await notifier.recordDspDeployment('p3', rec);
    _expectStatus(notifier, 'p3', TuneDeploymentStatus.applied);
    final profile = notifier.state.firstWhere((p) => p.id == 'p3');
    expect(profile.dspDeploymentRecord?.dspApplied, isTrue);
  });

  test('failed result (rollback failed) persists unknown, never dspApplied',
      () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.add(_profileWithId('p4'));
    await notifier.recordDspDeployment(
      'p4',
      _record(result: ConsumerDspDeploymentRecordResult.failed),
    );
    final profile = notifier.state.firstWhere((p) => p.id == 'p4');
    expect(profile.deploymentStatus, TuneDeploymentStatus.unknown);
    expect(profile.dspDeploymentRecord?.dspApplied, isFalse);
  });

  test('persisted applied reloads as unknown on app restart', () async {
    final notifier1 = ConsumerSoundProfileNotifier();
    await notifier1.add(_profileWithId('p5'));
    await notifier1.recordDspDeployment(
      'p5',
      _record(
        result: ConsumerDspDeploymentRecordResult.applied,
        dspApplied: true,
      ),
    );
    _expectStatus(notifier1, 'p5', TuneDeploymentStatus.applied);

    // Simulate app restart: a new notifier hydrates from SharedPreferences.
    final notifier2 = ConsumerSoundProfileNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final reloaded = notifier2.state.firstWhere((p) => p.id == 'p5');
    // After restart, applied → unknown (device may have been power-cycled).
    expect(reloaded.deploymentStatus, TuneDeploymentStatus.unknown);
    // Historical success metadata must remain intact.
    expect(reloaded.dspDeploymentRecord?.dspApplied, isTrue);
    expect(reloaded.dspDeploymentRecord?.result,
        ConsumerDspDeploymentRecordResult.applied);
  });

  test('notDeployed reloads as notDeployed (restart does not change it)',
      () async {
    final notifier1 = ConsumerSoundProfileNotifier();
    await notifier1.add(_profileWithId('p6'));
    await notifier1.recordDspDeployment(
      'p6',
      _record(result: ConsumerDspDeploymentRecordResult.blocked),
    );
    final notifier2 = ConsumerSoundProfileNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _expectStatus(notifier2, 'p6', TuneDeploymentStatus.notDeployed);
  });

  test('explicit reapplication in current session returns to applied', () async {
    final notifier1 = ConsumerSoundProfileNotifier();
    await notifier1.add(_profileWithId('p7'));
    await notifier1.recordDspDeployment(
      'p7',
      _record(
        result: ConsumerDspDeploymentRecordResult.applied,
        dspApplied: true,
      ),
    );

    // After restart, status becomes unknown.
    final notifier2 = ConsumerSoundProfileNotifier();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _expectStatus(notifier2, 'p7', TuneDeploymentStatus.unknown);

    // Explicit reapplication in the current session → applied again.
    await notifier2.recordDspDeployment(
      'p7',
      _record(
        result: ConsumerDspDeploymentRecordResult.applied,
        dspApplied: true,
      ),
    );
    _expectStatus(notifier2, 'p7', TuneDeploymentStatus.applied);
  });
});
}
