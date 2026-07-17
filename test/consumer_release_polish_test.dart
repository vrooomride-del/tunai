import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/features/ble/ble_controller.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/known_consumer_device.dart';
import 'package:tunai/features/device/consumer_device_screen.dart';
import 'package:tunai/features/more/about_tunai_screen.dart';
import 'package:tunai/features/more/factory_screen.dart';
import 'package:tunai/features/more/more_screen.dart';

class _Store implements KnownConsumerDevicePersistence {
  KnownConsumerDevice? value;
  _Store(this.value);
  @override
  Future<KnownConsumerDevice?> load() async => value;
  @override
  Future<void> save(KnownConsumerDevice device) async => value = device;
  @override
  Future<void> clear() async => value = null;
}

class _Driver implements ConsumerBleGattDriver {
  @override
  Future<bool> isBluetoothAvailable() async => true;
  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<List<ConsumerBleDevice>> scan({String? identifier}) async => [];
  @override
  Future<ConsumerBleConnection> connect(ConsumerBleDevice device) =>
      throw UnimplementedError();
}

KnownConsumerDevice _known() => KnownConsumerDevice(
      identifier: 'consumer-device-1',
      advertisedName: 'WONDOM ICP5',
      validatedProductIdentity: 'TUNAI ONE',
      lastSuccessfulConnectionAt: DateTime.now(),
      autoReconnectEnabled: true,
      lastDisconnectWasUserInitiated: true,
    );

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ko', 'KR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: child,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Factory Mode is hidden from normal MORE navigation',
      (tester) async {
    await tester.pumpWidget(ProviderScope(child: _app(const MoreScreen())));
    expect(find.text('CONNECTED DEVICE'), findsOneWidget);
    expect(find.text('SOUND PROFILES'), findsOneWidget);
    expect(find.text('HELP & SUPPORT'), findsOneWidget);
    expect(find.text('ABOUT TUNAI'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.textContaining('FACTORY'), findsNothing);
    expect(find.textContaining('Developer Simulation'), findsNothing);
    expect(find.textContaining('DSP QA'), findsNothing);
  });

  testWidgets('Factory Mode remains accessible through protected About path',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: AboutTunaiScreen()),
    ));
    await tester.longPress(find.byKey(const Key('factory_hidden_access')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('factory_pin_field')), '1234');
    await tester.tap(find.byKey(const Key('factory_pin_submit')));
    await tester.pumpAndSettle();
    expect(find.byType(FactoryScreen), findsOneWidget);
    expect(find.text('DEVICE INFORMATION'), findsOneWidget);
    expect(find.text('PRODUCTION TEST'), findsOneWidget);
    expect(find.text('CALIBRATION'), findsOneWidget);
    expect(find.text('MAINTENANCE'), findsOneWidget);
    expect(
        find.byKey(const Key('factory_engineering_section')), findsOneWidget);
  });

  for (final locale in const [Locale('en'), Locale('ko', 'KR')]) {
    testWidgets('release MORE copy is localized (${locale.languageCode})',
        (tester) async {
      await tester.pumpWidget(
          ProviderScope(child: _app(const MoreScreen(), locale: locale)));
      expect(
        find.text(locale.languageCode == 'ko' ? '연결된 기기' : 'CONNECTED DEVICE'),
        findsOneWidget,
      );
      expect(
        find.text(locale.languageCode == 'ko' ? '도움말 및 지원' : 'HELP & SUPPORT'),
        findsOneWidget,
      );
    });
  }

  testWidgets('known device is displayed and Forget Device clears storage',
      (tester) async {
    final store = _Store(_known());
    final service =
        ConsumerBleService(driver: _Driver(), knownDeviceStore: store);
    await tester.pumpWidget(ProviderScope(
      overrides: [consumerBleServiceProvider.overrideWithValue(service)],
      child: _app(const ConsumerDeviceScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('TUNAI ONE'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
    expect(find.textContaining('Today'), findsOneWidget);
    expect(store.value!.autoReconnectEnabled, isTrue);

    await tester.tap(find.byKey(const Key('device_forget_button')));
    await tester.pumpAndSettle();
    expect(store.value, isNull);
    expect(find.text('ON'), findsNothing);
  });

  testWidgets('normal release UI has no narrow-screen overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      child: _app(const MoreScreen(), locale: const Locale('ko', 'KR')),
    ));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Developer'), findsNothing);
  });
}
