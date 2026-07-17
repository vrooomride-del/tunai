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
import 'package:tunai/features/listen/listen_screen.dart';

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

ConsumerSoundProfile _appliedProfile() => ConsumerSoundProfile(
      id: 'plan-applied',
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: true,
      status: ConsumerProfileStatus.active,
      resultCards: _scan.cards,
      measurementId: 'measurement-applied',
      tunePlanId: 'plan-applied',
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.applied,
    );

// ── Widget helpers ────────────────────────────────────────────────────────────

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

/// Pump [AiScreen] with [applyPhase] pre-set and all required providers
/// overridden. Profile status is ready (not yet applied) unless [profile]
/// overrides it.
Future<void> _pumpAiWithPhase(
  WidgetTester tester, {
  required ConsumerApplyPhase applyPhase,
  ConsumerSoundProfile? profile,
}) async {
  final p = profile ?? _readyProfile();
  final profiles = ConsumerSoundProfileNotifier();
  await profiles.upsertGeneratedAndSelect(p);
  final scans = RoomScanResultNotifier();
  await scans.saveResult(_scan);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      consumerSoundProfileProvider.overrideWith((ref) => profiles),
      roomScanResultProvider.overrideWith((ref) => scans),
      speakerCheckResultProvider.overrideWith(
        (_) => SpeakerCheckResult.blocked(
          status: SpeakerCheckStatus.soundStateNotVerified,
          evaluatedAt: _created,
        ),
      ),
      consumerApplyPhaseProvider.overrideWith((_) => applyPhase),
    ],
    child: _app(AiScreen(onApplied: () {})),
  ));
  await tester.pump();
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Apply success — profile deployed → StateF ─────────────────────────────

  group('Apply success — applied profile shows Ready to listen', () {
    testWidgets('StateF: "Ready to listen." visible after apply', (tester) async {
      // Use add() to preserve isActive: true / deploymentStatus: applied.
      final profiles = ConsumerSoundProfileNotifier();
      await profiles.add(_appliedProfile());
      final scans = RoomScanResultNotifier();
      await scans.saveResult(_scan);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerSoundProfileProvider.overrideWith((ref) => profiles),
          roomScanResultProvider.overrideWith((ref) => scans),
          consumerApplyPhaseProvider.overrideWith(
            (_) => ConsumerApplyPhase.idle,
          ),
        ],
        child: _app(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.text('Ready to listen.'), findsOneWidget);
      expect(find.text('Go to LISTEN'), findsOneWidget);
      // No error/rollback UI visible.
      expect(find.byKey(const Key('consumer_apply_failed')), findsNothing);
      expect(find.byKey(const Key('consumer_apply_restored')), findsNothing);
    });

    testWidgets('StateF: Korean "들을 준비 완료." visible after apply',
        (tester) async {
      final profiles = ConsumerSoundProfileNotifier();
      await profiles.add(_appliedProfile());
      final scans = RoomScanResultNotifier();
      await scans.saveResult(_scan);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerSoundProfileProvider.overrideWith((ref) => profiles),
          roomScanResultProvider.overrideWith((ref) => scans),
          consumerApplyPhaseProvider.overrideWith(
            (_) => ConsumerApplyPhase.idle,
          ),
        ],
        child: _app(AiScreen(onApplied: () {}), locale: const Locale('ko')),
      ));
      await tester.pump();

      expect(find.text('들을 준비 완료.'), findsOneWidget);
      expect(find.text('LISTEN으로 이동'), findsOneWidget);
    });
  });

  // ── Applying state ────────────────────────────────────────────────────────

  group('Applying state — progress shown', () {
    testWidgets('"Applying to speaker…" visible during apply', (tester) async {
      await _pumpAiWithPhase(tester, applyPhase: ConsumerApplyPhase.applying);

      expect(
        find.byKey(const Key('consumer_apply_applying')),
        findsOneWidget,
      );
      expect(find.text('Applying to speaker...'), findsOneWidget);
      expect(find.text('Please wait.'), findsOneWidget);
      // No success/failure UI visible.
      expect(find.text('Ready to listen.'), findsNothing);
      expect(find.byKey(const Key('consumer_apply_failed')), findsNothing);
    });

    testWidgets('Korean applying text visible', (tester) async {
      final profiles = ConsumerSoundProfileNotifier();
      await profiles.upsertGeneratedAndSelect(_readyProfile());
      final scans = RoomScanResultNotifier();
      await scans.saveResult(_scan);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerSoundProfileProvider.overrideWith((ref) => profiles),
          roomScanResultProvider.overrideWith((ref) => scans),
          speakerCheckResultProvider.overrideWith(
            (_) => SpeakerCheckResult.blocked(
              status: SpeakerCheckStatus.soundStateNotVerified,
              evaluatedAt: _created,
            ),
          ),
          consumerApplyPhaseProvider.overrideWith(
            (_) => ConsumerApplyPhase.applying,
          ),
        ],
        child: _app(AiScreen(onApplied: () {}), locale: const Locale('ko')),
      ));
      await tester.pump();

      expect(find.text('스피커에 적용 중...'), findsOneWidget);
      expect(find.text('잠시 기다려 주세요.'), findsOneWidget);
    });
  });

  // ── Apply failure UI state ────────────────────────────────────────────────

  group('Apply failure — clear user-friendly message', () {
    testWidgets('failed phase shows "Something went wrong"', (tester) async {
      await _pumpAiWithPhase(tester, applyPhase: ConsumerApplyPhase.failed);

      expect(find.byKey(const Key('consumer_apply_failed')), findsOneWidget);
      expect(find.text('Something went wrong.'), findsOneWidget);
      expect(
        find.text('Please reconnect your speaker and try again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      // Does not show applied UI.
      expect(find.text('Ready to listen.'), findsNothing);
    });

    testWidgets('Korean: failed phase shows correct message', (tester) async {
      final profiles = ConsumerSoundProfileNotifier();
      await profiles.upsertGeneratedAndSelect(_readyProfile());
      final scans = RoomScanResultNotifier();
      await scans.saveResult(_scan);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerSoundProfileProvider.overrideWith((ref) => profiles),
          roomScanResultProvider.overrideWith((ref) => scans),
          speakerCheckResultProvider.overrideWith(
            (_) => SpeakerCheckResult.blocked(
              status: SpeakerCheckStatus.soundStateNotVerified,
              evaluatedAt: _created,
            ),
          ),
          consumerApplyPhaseProvider.overrideWith(
            (_) => ConsumerApplyPhase.failed,
          ),
        ],
        child: _app(AiScreen(onApplied: () {}), locale: const Locale('ko')),
      ));
      await tester.pump();

      expect(find.text('문제가 발생했습니다.'), findsOneWidget);
      expect(find.text('스피커를 재연결하고 다시 시도해 주세요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('failed: no DSP/technical language visible', (tester) async {
      await _pumpAiWithPhase(tester, applyPhase: ConsumerApplyPhase.failed);

      // No engineering terminology in UI.
      expect(find.textContaining('DSP'), findsNothing);
      expect(find.textContaining('PEQ'), findsNothing);
      expect(find.textContaining('ACK'), findsNothing);
      expect(find.textContaining('rollback'), findsNothing);
    });
  });

  // ── Restored state handling ───────────────────────────────────────────────

  group('Restored state — previous settings safe message', () {
    testWidgets('restored phase: "No changes were made." visible', (tester) async {
      await _pumpAiWithPhase(tester, applyPhase: ConsumerApplyPhase.restored);

      expect(find.byKey(const Key('consumer_apply_restored')), findsOneWidget);
      expect(find.text('No changes were made.'), findsOneWidget);
      expect(
        find.text(
            'Your speaker\'s original sound remains active.\n'
            'Your previous settings are safe.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);
      // Does not show failed UI or applied UI.
      expect(find.byKey(const Key('consumer_apply_failed')), findsNothing);
      expect(find.text('Ready to listen.'), findsNothing);
    });

    testWidgets('Korean: restored phase shows correct message', (tester) async {
      final profiles = ConsumerSoundProfileNotifier();
      await profiles.upsertGeneratedAndSelect(_readyProfile());
      final scans = RoomScanResultNotifier();
      await scans.saveResult(_scan);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerSoundProfileProvider.overrideWith((ref) => profiles),
          roomScanResultProvider.overrideWith((ref) => scans),
          speakerCheckResultProvider.overrideWith(
            (_) => SpeakerCheckResult.blocked(
              status: SpeakerCheckStatus.soundStateNotVerified,
              evaluatedAt: _created,
            ),
          ),
          consumerApplyPhaseProvider.overrideWith(
            (_) => ConsumerApplyPhase.restored,
          ),
        ],
        child: _app(AiScreen(onApplied: () {}), locale: const Locale('ko')),
      ));
      await tester.pump();

      expect(find.text('변경되지 않았습니다.'), findsOneWidget);
      expect(find.text('스피커의 원래 사운드가 그대로 유지됩니다.\n이전 설정은 안전하게 보존되어 있습니다.'),
          findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);
    });

    testWidgets('restored: no technical language visible', (tester) async {
      await _pumpAiWithPhase(tester, applyPhase: ConsumerApplyPhase.restored);

      expect(find.textContaining('DSP'), findsNothing);
      expect(find.textContaining('rollback'), findsNothing);
      expect(find.textContaining('PEQ'), findsNothing);
    });
  });

  // ── consumerApplyPhaseProvider default ───────────────────────────────────

  group('consumerApplyPhaseProvider', () {
    test('starts at idle on fresh launch', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(consumerApplyPhaseProvider),
        ConsumerApplyPhase.idle,
      );
    });
  });

  // ── Listen screen — Listening Level terminology ───────────────────────────

  group('Listen screen — Listening Level terminology', () {
    testWidgets('"Listening Level" appears, "Master Volume" does not',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _app(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.text('Listening Level'), findsOneWidget);
      expect(find.textContaining('Master Volume'), findsNothing);
    });

    testWidgets('Korean listen screen shows "듣기 음량", not "Master Volume"',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _app(const ListenScreen(), locale: const Locale('ko')),
      ));
      await tester.pump();

      expect(find.text('듣기 음량'), findsOneWidget);
      expect(find.textContaining('Master Volume'), findsNothing);
    });

    testWidgets('Level presets Low/Comfortable/Lively visible', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _app(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Comfortable'), findsOneWidget);
      expect(find.text('Lively'), findsOneWidget);
    });
  });
}
