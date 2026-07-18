import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_dsp_deployment.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/core/dsp_state_synchronization.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/speaker_check_gate.dart';
import 'package:tunai/core/speaker_state_verification.dart';
import 'package:tunai/features/ai/ai_screen.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

final _created = DateTime.utc(2025, 7, 1);

final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: const [],
);

ConsumerSoundProfile _readyProfile() => ConsumerSoundProfile(
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

// ── Widget pump helper ────────────────────────────────────────────────────────

Widget _app(AiScreen child, {Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko')],
      home: child,
    );

Future<void> _pumpWithCheck(
  WidgetTester tester, {
  required SpeakerCheckResult check,
}) async {
  final profiles = ConsumerSoundProfileNotifier();
  await profiles.upsertGeneratedAndSelect(_readyProfile());
  final scans = RoomScanResultNotifier();
  await scans.saveResult(_scan);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      consumerSoundProfileProvider.overrideWith((ref) => profiles),
      roomScanResultProvider.overrideWith((ref) => scans),
      speakerCheckResultProvider.overrideWith((_) => check),
    ],
    child: _app(AiScreen(onApplied: () {})),
  ));
  await tester.pump();
}

// ── Fake transport for unit tests ─────────────────────────────────────────────

class _FakeTransport implements ConsumerDspTransport {
  @override
  final bool connected;
  @override
  final bool handshakeValidated;
  @override
  final String? deviceIdentifier;

  const _FakeTransport({
    this.connected = false,
    this.handshakeValidated = false,
    this.deviceIdentifier,
  });

  @override
  Future<List<int>> writeAndAwaitResponse(
    List<int> command, {
    required Duration timeout,
  }) async =>
      const [];
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Unit: SpeakerCheckResult lifecycle ───────────────────────────────────

  group('SpeakerCheckResult — persistence contract', () {
    test('verified result serialises to notVerified — no false restore',
        () {
      final verified = SpeakerCheckResult.verified(
        speakerId: 'tunai-one-A1B2C3',
        evaluatedAt: _created,
      );
      expect(verified.readyToApply, isTrue);
      expect(
        verified.toPersistedState(),
        SpeakerCheckPersistedState.notVerified,
        reason: 'A session-verified result must never be restored as verified',
      );
    });

    test('persisted enum has only notVerified — no silent upgrade path', () {
      const values = SpeakerCheckPersistedState.values;
      expect(values, hasLength(1));
      expect(values.single, SpeakerCheckPersistedState.notVerified);
    });
  });

  // ── Unit: speakerCheckPersistedStateProvider ──────────────────────────────

  group('speakerCheckPersistedStateProvider', () {
    test('always returns notVerified regardless of session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(speakerCheckPersistedStateProvider),
        SpeakerCheckPersistedState.notVerified,
      );
    });
  });

  // ── Unit: dspStateSnapshotProvider default ────────────────────────────────

  group('dspStateSnapshotProvider', () {
    test('starts null — no phantom snapshot on app launch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(dspStateSnapshotProvider), isNull);
    });
  });

  // ── Unit: restart safety via SpeakerStateVerification ────────────────────

  group('Speaker Check — restart does not falsely claim verified', () {
    test('disconnected transport + null snapshot → not readyToApply', () {
      const transport = _FakeTransport(
        connected: false,
        handshakeValidated: false,
        deviceIdentifier: null,
      );
      final result = SpeakerStateVerification.evaluate(
        transport: transport,
        expectedSpeakerId: 'tunai-one-A1B2C3',
        requiredStates: const [DspPeqStateRequest(channel: 1, bandId: 0)],
        snapshot: null,
      );
      expect(result.readyToApply, isFalse,
          reason: 'App restart with no snapshot must not be readyToApply');
    });
  });

  // ── Widget: ready speaker enables Apply ───────────────────────────────────

  group('Speaker Check — ready speaker enables Apply', () {
    testWidgets('readyToApply → "Apply to Speaker" button visible and enabled',
        (tester) async {
      await _pumpWithCheck(
        tester,
        check: SpeakerCheckResult.verified(
          speakerId: 'tunai-one-A1B2C3',
          evaluatedAt: _created,
        ),
      );

      expect(find.text('Apply to Speaker'), findsOneWidget);
      expect(find.text('Check Speaker'), findsNothing);
      // Verification notice is hidden when check passes.
      expect(
        find.byKey(const Key('consumer_dsp_state_verification_required')),
        findsNothing,
      );
    });
  });

  // ── Widget: disconnected speaker blocks Apply ─────────────────────────────

  group('Speaker Check — disconnected speaker', () {
    testWidgets('speakerNotConnected → Verification Required + connection hint',
        (tester) async {
      await _pumpWithCheck(
        tester,
        check: SpeakerCheckResult.blocked(
          status: SpeakerCheckStatus.speakerNotConnected,
          evaluatedAt: _created,
        ),
      );

      expect(find.text('Check Speaker'), findsOneWidget);
      expect(find.text('Apply to Speaker'), findsNothing);
      expect(
        find.byKey(const Key('consumer_dsp_state_verification_required')),
        findsOneWidget,
      );
      expect(find.text('Check speaker connection.'), findsOneWidget);
    });
  });

  // ── Widget: identity mismatch blocks Apply ────────────────────────────────

  group('Speaker Check — identity mismatch', () {
    testWidgets('speakerMismatch → identity notice, no Apply button',
        (tester) async {
      await _pumpWithCheck(
        tester,
        check: SpeakerCheckResult.blocked(
          status: SpeakerCheckStatus.speakerMismatch,
          evaluatedAt: _created,
        ),
      );

      expect(find.text('Check Speaker'), findsOneWidget);
      expect(find.text('Apply to Speaker'), findsNothing);
      expect(
        find.text('Speaker identity could not be confirmed.'),
        findsOneWidget,
      );
    });

    testWidgets('identityUnconfirmed → identity notice', (tester) async {
      await _pumpWithCheck(
        tester,
        check: SpeakerCheckResult.blocked(
          status: SpeakerCheckStatus.identityUnconfirmed,
          evaluatedAt: _created,
        ),
      );

      expect(
          find.text('Speaker identity could not be confirmed.'), findsOneWidget);
      expect(find.text('Apply to Speaker'), findsNothing);
    });
  });

  // ── Widget: missing original values blocks Apply ──────────────────────────

  group('Speaker Check — missing original values', () {
    testWidgets('originalValuesUnavailable → generic verification notice',
        (tester) async {
      await _pumpWithCheck(
        tester,
        check: SpeakerCheckResult.blocked(
          status: SpeakerCheckStatus.originalValuesUnavailable,
          evaluatedAt: _created,
          missingStateReasons: const ['Band 0 (channel 1)'],
        ),
      );

      expect(find.text('Check Speaker'), findsOneWidget);
      expect(find.text('Apply to Speaker'), findsNothing);
      expect(
        find.byKey(const Key('consumer_dsp_state_verification_required')),
        findsOneWidget,
      );
      expect(
        find.text('Check your speaker before applying.'),
        findsOneWidget,
      );
    });

    testWidgets('soundStateNotVerified → generic verification notice',
        (tester) async {
      await _pumpWithCheck(
        tester,
        check: SpeakerCheckResult.blocked(
          status: SpeakerCheckStatus.soundStateNotVerified,
          evaluatedAt: _created,
        ),
      );

      expect(
        find.text('Check your speaker before applying.'),
        findsOneWidget,
      );
      expect(find.text('Apply to Speaker'), findsNothing);
    });
  });
}
