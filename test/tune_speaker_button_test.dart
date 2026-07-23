// Tests for the TUNE apply/check button ("스피커 확인 필요" / "Check Speaker").
// The button must never be a dead disabled control: on tap it re-checks live
// state and routes (apply / connect / Bluetooth / reconnect).

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/speaker_check_gate.dart';
import 'package:tunai/core/speaker_state_verification.dart';
import 'package:tunai/core/speaker_verification_session.dart';
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

// These tests are about the SpeakerButtonAction routing, not about
// TuneAvailability branching, so they always provide a real, non-empty
// TunePlan matching _readyGeneratedProfile's tunePlanId — evaluateTuneAvailability
// (tune_availability.dart) resolves that to readyToApply, which is what all
// of these tests need to reach _StateEReadyToApply in the first place.
final _readyTunePlan = TunePlan(
  id: 'plan-ready',
  sourceMeasurementId: 'measurement-ready',
  createdAt: _created,
  bands: const [
    TuneCorrectionBand(
      frequencyHz: 120,
      gainDb: -4,
      q: 2,
      evidenceReference: 'measurement-ready:peak:120',
      safetyValidated: true,
    ),
  ],
  rejectedCandidates: const [],
  safetyBounds: const TuneSafetyBounds(),
  measurementQuality: CaptureQualityStatus.valid,
  measurementConsistency: 1,
  warnings: const [],
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
  // Defaults to true so existing "DSP-ready" scenarios keep testing exactly
  // what they said they test; only the new tests below flip it to exercise
  // the audio-confirmation gate itself.
  bool audioConfirmed = true,
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
      audioSpeakerConfirmedProvider.overrideWith((_) => audioConfirmed),
      audioSpeakerConfirmationStaleProvider.overrideWith((_) => false),
      currentTunePlanProvider.overrideWith((ref) async => _readyTunePlan),
    ],
    child: _app(AiScreen(onApplied: () {}, onGoTo: onGoTo)),
  ));
  // currentTunePlanProvider is a FutureProvider — one extra pump lets it
  // settle from loading to data before assertions run.
  await tester.pump();
  await tester.pump();
}

SpeakerCheckResult _blocked(SpeakerCheckStatus status) =>
    SpeakerCheckResult.blocked(status: status, evaluatedAt: _created);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Pure routing decision ─────────────────────────────────────────────────

  group('resolveSpeakerButtonAction', () {
    test('ready + audio confirmed → apply (continue)', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.readyToApply,
          connection: BleConnectionState.connected,
          audioConfirmed: true,
        ),
        SpeakerButtonAction.apply,
      );
    });

    test('ready but audio NOT confirmed → confirmSpeaker (never a silent '
        'apply on an unconfirmed audio path)', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.readyToApply,
          connection: BleConnectionState.connected,
          audioConfirmed: false,
        ),
        SpeakerButtonAction.confirmSpeaker,
      );
    });

    test('not connected → connect', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.speakerNotConnected,
          connection: BleConnectionState.disconnected,
          audioConfirmed: false,
        ),
        SpeakerButtonAction.connect,
      );
    });

    test('Bluetooth off takes priority → bluetoothOff', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.speakerNotConnected,
          connection: BleConnectionState.bluetoothOff,
          audioConfirmed: false,
        ),
        SpeakerButtonAction.bluetoothOff,
      );
    });

    test('connected but sound state not verified → reconnect', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.soundStateNotVerified,
          connection: BleConnectionState.connected,
          audioConfirmed: false,
        ),
        SpeakerButtonAction.reconnect,
      );
    });

    test('identity unconfirmed → reconnect', () {
      expect(
        resolveSpeakerButtonAction(
          status: SpeakerCheckStatus.identityUnconfirmed,
          connection: BleConnectionState.connected,
          audioConfirmed: false,
        ),
        SpeakerButtonAction.reconnect,
      );
    });

    test('never resolves to a no-op for any status/connection/audio combination',
        () {
      for (final status in SpeakerCheckStatus.values) {
        for (final connection in BleConnectionState.values) {
          for (final audioConfirmed in [true, false]) {
            final action = resolveSpeakerButtonAction(
                status: status,
                connection: connection,
                audioConfirmed: audioConfirmed);
            expect(action, isA<SpeakerButtonAction>());
          }
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

    testWidgets(
        'DSP-ready but audio Speaker Check not confirmed: label stays '
        '"Check Speaker" and tapping routes to ROOM, never a silent apply',
        (tester) async {
      final nav = <int>[];
      await _pumpStateE(
        tester,
        check: SpeakerCheckResult.verified(
            speakerId: 'spk-1', evaluatedAt: _created),
        audioConfirmed: false,
        onGoTo: nav.add,
      );

      expect(find.text('Apply to Speaker'), findsNothing);
      expect(find.text('Check Speaker'), findsOneWidget);
      await tester.tap(find.text('Check Speaker'));
      await tester.pump();

      // Routes to the ROOM tab (index 1), where the Speaker Check tone lives.
      expect(nav, [1]);
      expect(
          find.text('Complete the speaker check in the ROOM tab first.'),
          findsOneWidget);
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
          currentTunePlanProvider.overrideWith((ref) async => _readyTunePlan),
        ],
        child: _app(AiScreen(onApplied: () {}, onGoTo: nav.add),
            locale: const Locale('ko')),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('스피커 확인 필요'));
      await tester.pump();

      expect(nav, [0]);
      expect(find.text('스피커를 먼저 연결해 주세요.'), findsOneWidget);
    });
  });
}
