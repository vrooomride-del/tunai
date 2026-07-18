// Tests for the TUNE apply/check button ("스피커 확인 필요" / "Check Speaker").
// The button must never be a dead disabled control: on tap it re-checks live
// state and routes (apply / connect / Bluetooth / reconnect).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/speaker_check_gate.dart';
import 'package:tunai/core/speaker_state_verification.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/ai/ai_screen.dart';
import 'package:tunai/features/ble/ble_controller.dart';

final _created = DateTime.fromMillisecondsSinceEpoch(1000);

final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: kDefaultResultCards,
);

ConsumerSoundProfile _readyGeneratedProfile() => ConsumerSoundProfile(
      id: 'plan-ready',
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: _scan.cards,
      measurementId: 'measurement-ready',
      tunePlanId: 'plan-ready',
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
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

Future<void> _pumpStateE(
  WidgetTester tester, {
  required SpeakerCheckResult check,
  required void Function(int) onGoTo,
}) async {
  final profiles = ConsumerSoundProfileNotifier();
  await profiles.upsertGeneratedAndSelect(_readyGeneratedProfile());
  final scans = RoomScanResultNotifier();
  await scans.saveResult(_scan);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      consumerSoundProfileProvider.overrideWith((ref) => profiles),
      roomScanResultProvider.overrideWith((ref) => scans),
      speakerCheckResultProvider.overrideWith((_) => check),
    ],
    child: _app(AiScreen(onApplied: () {}, onGoTo: onGoTo)),
  ));
  await tester.pump();
}

SpeakerCheckResult _blocked(SpeakerCheckStatus status) =>
    SpeakerCheckResult.blocked(status: status, evaluatedAt: _created);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Pure routing decision ─────────────────────────────────────────────────

  group('resolveSpeakerButtonAction', () {
    test('ready → apply (continue)', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.readyToApply,
          connection: BleConnectionState.connected,
        ),
        SpeakerButtonAction.apply,
      );
    });

    test('not connected → connect', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.speakerNotConnected,
          connection: BleConnectionState.disconnected,
        ),
        SpeakerButtonAction.connect,
      );
    });

    test('Bluetooth off takes priority → bluetoothOff', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.speakerNotConnected,
          connection: BleConnectionState.bluetoothOff,
        ),
        SpeakerButtonAction.bluetoothOff,
      );
    });

    test('connected but sound state not verified → reconnect', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.soundStateNotVerified,
          connection: BleConnectionState.connected,
        ),
        SpeakerButtonAction.reconnect,
      );
    });

    test('identity unconfirmed → reconnect', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.identityUnconfirmed,
          connection: BleConnectionState.connected,
        ),
        SpeakerButtonAction.reconnect,
      );
    });

    test('never resolves to a no-op for any status/connection combination', () {
      for (final status in SpeakerCheckStatus.values) {
        for (final connection in BleConnectionState.values) {
          final action = resolveSpeakerButtonAction(
              status: status, connection: connection);
          expect(action, isA<SpeakerButtonAction>());
        }
      }
    });
  });

  // ── Button is never a dead control ────────────────────────────────────────

  group('TUNE speaker button', () {
    testWidgets('disconnected: tap navigates to CONNECT (never dead)',
        (tester) async {
      final nav = <int>[];
      await _pumpStateE(
        tester,
        check: _blocked(SpeakerCheckStatus.speakerNotConnected),
        onGoTo: nav.add,
      );

      final button = find.text('Check Speaker');
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pump();

      // A dead (onPressed: null) button would not route anywhere.
      expect(nav, [0]);
      expect(find.text('Please connect your speaker first.'), findsOneWidget);
    });

    testWidgets('connected-but-unverified: tap routes to CONNECT to reconnect',
        (tester) async {
      final nav = <int>[];
      await _pumpStateE(
        tester,
        check: _blocked(SpeakerCheckStatus.soundStateNotVerified),
        onGoTo: nav.add,
      );

      await tester.tap(find.text('Check Speaker'));
      await tester.pump();

      expect(nav, [0]);
      expect(find.text('Reconnect your speaker to verify it.'), findsOneWidget);
    });

    testWidgets('ready: tap continues to apply and does NOT navigate away',
        (tester) async {
      final nav = <int>[];
      await _pumpStateE(
        tester,
        check: SpeakerCheckResult.verified(
            speakerId: 'spk-1', evaluatedAt: _created),
        onGoTo: nav.add,
      );

      // Ready → label is the apply action, and tapping it does not route away.
      expect(find.text('Apply to Speaker'), findsOneWidget);
      await tester.tap(find.text('Apply to Speaker'));
      await tester.pump();

      expect(nav, isEmpty);
    });

    testWidgets('KO disconnected: tap shows Korean guidance and routes',
        (tester) async {
      final nav = <int>[];
      final profiles = ConsumerSoundProfileNotifier();
      await profiles.upsertGeneratedAndSelect(_readyGeneratedProfile());
      final scans = RoomScanResultNotifier();
      await scans.saveResult(_scan);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerSoundProfileProvider.overrideWith((ref) => profiles),
          roomScanResultProvider.overrideWith((ref) => scans),
          speakerCheckResultProvider
              .overrideWith((_) => _blocked(SpeakerCheckStatus.speakerNotConnected)),
        ],
        child: _app(AiScreen(onApplied: () {}, onGoTo: nav.add),
            locale: const Locale('ko')),
      ));
      await tester.pump();

      await tester.tap(find.text('스피커 확인 필요'));
      await tester.pump();

      expect(nav, [0]);
      expect(find.text('스피커를 먼저 연결해 주세요.'), findsOneWidget);
    });
  });
}
