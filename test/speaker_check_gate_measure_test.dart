// Speaker Check is now a mandatory gate before measurement: the OS gives the
// app no way to confirm which device is actually playing audio, so the
// user's own "예/아니요" confirmation is the only real signal. "공간 분석
// 시작" must stay disabled until the user explicitly confirms they heard the
// tone from their connected speaker.
//
// Note: this file cannot drive the confirmation tone playback itself —
// just_audio has no real platform channel in the widget test harness and
// AudioPlayer.play() does not reliably resolve here (see
// splash_screen_test.dart for the same documented limitation), so
// `_hasPlayedOnce` never flips and the Yes/No question never appears in this
// environment. What IS verified here — that the gate starts closed and that
// tapping Start while unconfirmed never starts a measurement — is the part
// that matters most to prove by test; the "예 → enabled" / "아니요 → stays
// disabled" transitions must be confirmed on a real device.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/features/ble/ble_controller.dart';
import 'package:tunai/features/ble/consumer_ble_service.dart';
import 'package:tunai/features/ble/icp5_consumer_frame_codec.dart';
import 'package:tunai/features/measure/measure_screen.dart';
import 'package:tunai/features/measurement/measurement_controller.dart';

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
    name: 'Test Speaker',
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

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko')],
      home: child,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      '"공간 분석 시작" is disabled with guidance shown before the speaker '
      'check is confirmed, and tapping it never starts a measurement',
      (tester) async {
    final service = ConsumerBleService(driver: _Driver());
    await service.scan();
    await service.connect();

    await tester.pumpWidget(ProviderScope(
      overrides: [consumerBleServiceProvider.overrideWithValue(service)],
      child: _app(MeasureScreen(onMeasured: () {})),
    ));
    await tester.pump();

    // Intro screen → Mic Check.
    await tester.tap(find.text('공간 분석 시작'));
    await tester.pump();

    expect(find.text('먼저 연결된 스피커에서 확인음이 들리는지 확인해주세요.'),
        findsOneWidget);
    // The "did you hear it" question must not be answerable before the user
    // has actually attempted to play the tone at least once.
    expect(find.text('예'), findsNothing);
    expect(find.text('아니요'), findsNothing);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(MeasureScreen)));
    await tester.tap(find.text('공간 분석 시작'));
    await tester.pump();
    expect(container.read(measurementProvider).step, MeasurementStep.idle);
  });
}
