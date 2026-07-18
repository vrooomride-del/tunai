import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/speaker_check_gate.dart';
import 'package:tunai/features/ai/ai_screen.dart';
import 'package:tunai/features/listen/listen_screen.dart';

Widget _en(Widget child) => MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko', 'KR')],
      home: child,
    );

Widget _ko(Widget child) => MaterialApp(
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko', 'KR')],
      home: child,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Apply flow — consumer messages ─────────────────────────────────────────

  group('Apply flow — applying state consumer text', () {
    testWidgets('EN: applying shows consumer-friendly text, no DSP jargon',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerApplyPhaseProvider
              .overrideWith((ref) => ConsumerApplyPhase.applying),
        ],
        child: _en(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.byKey(const Key('consumer_apply_applying')), findsOneWidget);
      expect(
        find.text('Applying your personal sound to the speaker...'),
        findsOneWidget,
      );
      expect(find.textContaining('DSP'), findsNothing);
      expect(find.textContaining('PEQ'), findsNothing);
    });

    testWidgets('KO: applying shows Korean consumer text', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerApplyPhaseProvider
              .overrideWith((ref) => ConsumerApplyPhase.applying),
        ],
        child: _ko(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(
        find.text('나만의 사운드를 스피커에 적용하고 있습니다.'),
        findsOneWidget,
      );
    });
  });

  group('Apply flow — restored state consumer text', () {
    testWidgets('EN: restored shows "Could not apply" headline, no "rollback"',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerApplyPhaseProvider
              .overrideWith((ref) => ConsumerApplyPhase.restored),
        ],
        child: _en(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.byKey(const Key('consumer_apply_restored')), findsOneWidget);
      expect(find.text('Could not apply.'), findsOneWidget);
      expect(find.textContaining('previous settings'), findsOneWidget);
      expect(find.textContaining('rollback'), findsNothing);
    });

    testWidgets('KO: restored shows "적용하지 못했습니다." + "이전 설정"', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerApplyPhaseProvider
              .overrideWith((ref) => ConsumerApplyPhase.restored),
        ],
        child: _ko(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.text('적용하지 못했습니다.'), findsOneWidget);
      expect(find.textContaining('이전 설정'), findsOneWidget);
    });
  });

  group('Apply flow — failed state consumer text', () {
    testWidgets('EN: failed shows "Could not apply" headline', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerApplyPhaseProvider
              .overrideWith((ref) => ConsumerApplyPhase.failed),
        ],
        child: _en(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.byKey(const Key('consumer_apply_failed')), findsOneWidget);
      expect(find.text('Could not apply.'), findsOneWidget);
    });

    testWidgets('KO: failed shows "적용하지 못했습니다."', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          consumerApplyPhaseProvider
              .overrideWith((ref) => ConsumerApplyPhase.failed),
        ],
        child: _ko(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.text('적용하지 못했습니다.'), findsOneWidget);
    });
  });

  // ── Listen screen — simplified consumer UI ─────────────────────────────────

  group('Listen screen — no technical engineering status', () {
    testWidgets('No "System Health" engineering row visible', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.textContaining('System Health'), findsNothing);
    });

    testWidgets('KO: no "시스템 상태" row visible', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _ko(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.textContaining('시스템 상태'), findsNothing);
    });

    testWidgets('A/B toggle does not show "ACOUSTIC TUNE" label',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.text('ACOUSTIC TUNE'), findsNothing);
    });

    testWidgets('No "Room Analysis" text on listen screen', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.textContaining('Room Analysis'), findsNothing);
    });

    testWidgets('No DSP technical terms on listen screen', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(const ListenScreen()),
      ));
      await tester.pump();

      expect(find.textContaining('DSP'), findsNothing);
      expect(find.textContaining('PEQ'), findsNothing);
    });
  });

  // ── ai_screen.dart state A — no DSP terms ────────────────────────────────

  group('Tune screen state A — no device connected', () {
    testWidgets('EN: state A shows no DSP terms', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.textContaining('DSP'), findsNothing);
      expect(find.textContaining('PEQ'), findsNothing);
      expect(find.textContaining('state verification'), findsNothing);
    });

    testWidgets('KO: state A shows consumer speaker prompt', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _ko(AiScreen(onApplied: () {})),
      ));
      await tester.pump();

      expect(find.textContaining('스피커'), findsWidgets);
    });
  });
}
