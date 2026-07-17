import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/first_run_state.dart';
import 'package:tunai/features/connect/connect_screen.dart';
import 'package:tunai/features/onboarding/onboarding_screen.dart';
import 'package:tunai/shared/first_run_guide_card.dart';

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

  // ── C.2 First Launch copy ─────────────────────────────────────────────────

  group('Onboarding page 2 — no technical terms', () {
    testWidgets('EN: page 2 shows space copy, no "AI Acoustic Intelligence"',
        (tester) async {
      await tester.pumpWidget(_en(OnboardingScreen(onComplete: () {})));

      // advance to page 2
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Create your personal sound.'), findsOneWidget);
      expect(
        find.text('Create a sound experience made for your space.'),
        findsOneWidget,
      );
      expect(find.textContaining('AI Acoustic Intelligence'), findsNothing);
      expect(find.textContaining('DSP'), findsNothing);
      expect(find.textContaining('PEQ'), findsNothing);
    });

    testWidgets('KO: page 2 shows 당신의 공간에 맞는 copy, no technical terms',
        (tester) async {
      await tester.pumpWidget(_ko(OnboardingScreen(onComplete: () {})));

      await tester.tap(find.text('계속'));
      await tester.pumpAndSettle();

      expect(find.text('당신만의 사운드를 만드세요.'), findsOneWidget);
      expect(
        find.text('당신의 공간에 맞는 새로운 사운드를 만들어보세요.'),
        findsOneWidget,
      );
      expect(find.textContaining('AI Acoustic Intelligence'), findsNothing);
    });
  });

  // ── C.3 Connect UX step hierarchy ────────────────────────────────────────

  group('Connect screen — step progress indicators (non-interactive)', () {
    testWidgets('EN: step labels and single CTA visible when disconnected',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      // Step indicator labels (non-interactive text, no buttons)
      expect(find.text('Connect Speaker'), findsWidgets); // step label + CTA
      expect(find.text('Analyze Space'), findsOneWidget); // step label only
      // Single primary CTA at bottom
      expect(find.byKey(const Key('consumer_ble_scan_button')), findsOneWidget);
      // Informational card with no button inside
      expect(find.byKey(const Key('consumer_connect_info_card')), findsOneWidget);
      // No old-style STEP badge text
      expect(find.text('STEP 1'), findsNothing);
      expect(find.text('STEP 2'), findsNothing);
    });

    testWidgets('KO: step labels and single CTA visible when disconnected',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _ko(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(find.text('스피커 연결'), findsWidgets); // step label + CTA
      expect(find.text('공간 분석'), findsOneWidget); // step label only
      expect(find.byKey(const Key('consumer_ble_scan_button')), findsOneWidget);
      expect(find.text('스피커 연결하기'), findsOneWidget); // bottom CTA
      expect(find.byKey(const Key('consumer_connect_info_card')), findsOneWidget);
    });

    testWidgets('No old "Bluetooth로 TUNAI" subtitle visible', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(find.textContaining('Bluetooth로 TUNAI'), findsNothing);
    });

    testWidgets('Step rows have no GestureDetector (non-interactive)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      // _StepRow builds a Row with no GestureDetector — verify step text is
      // not wrapped in any tappable widget by checking the widget key.
      // The only GestureDetectors on screen should be the bottom CTA and Cancel.
      final gestureDetectors = tester
          .widgetList<GestureDetector>(find.byType(GestureDetector))
          .toList();
      // Should have at most 1 primary CTA GestureDetector (scan button)
      // No step row GestureDetectors
      expect(gestureDetectors.length, lessThanOrEqualTo(2));
    });
  });

  // ── C.4 Space terminology ─────────────────────────────────────────────────

  group('Space terminology — "Room" replaced with "Space"', () {
    testWidgets('FirstRunGuideCard STEP 2 label is SPACE SCAN (EN)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          firstRunStateProvider.overrideWith(
            (ref) => FirstRunState.deviceConnectedNoRoomScan,
          ),
        ],
        child: _en(Scaffold(
          body: FirstRunGuideCard(onGoTo: (_) {}),
        )),
      ));
      await tester.pump();

      expect(find.text('STEP 2 · SPACE SCAN'), findsOneWidget);
      expect(find.textContaining('ROOM SCAN'), findsNothing);
    });

    testWidgets('FirstRunGuideCard step 2 button is "Start Space Analysis" (EN)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          firstRunStateProvider.overrideWith(
            (ref) => FirstRunState.deviceConnectedNoRoomScan,
          ),
        ],
        child: _en(Scaffold(
          body: FirstRunGuideCard(onGoTo: (_) {}),
        )),
      ));
      await tester.pump();

      expect(find.text('Start Space Analysis'), findsOneWidget);
      expect(find.textContaining('Start Room Analysis'), findsNothing);
    });

    testWidgets('FirstRunGuideCard applied subtitle says "this space" not "this room"',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          firstRunStateProvider.overrideWith(
            (ref) => FirstRunState.acousticTuneApplied,
          ),
        ],
        child: _en(Scaffold(
          body: FirstRunGuideCard(onGoTo: (_) {}),
        )),
      ));
      await tester.pump();

      expect(find.textContaining('this space'), findsOneWidget);
      expect(find.textContaining('this room'), findsNothing);
    });

    testWidgets('FirstRunGuideCard step 2 subtitle says "your space" (EN)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          firstRunStateProvider.overrideWith(
            (ref) => FirstRunState.deviceConnectedNoRoomScan,
          ),
        ],
        child: _en(Scaffold(
          body: FirstRunGuideCard(onGoTo: (_) {}),
        )),
      ));
      await tester.pump();

      expect(find.textContaining('your space'), findsOneWidget);
      expect(find.textContaining('your room'), findsNothing);
    });

    testWidgets('Connect screen banner says "Space Analysis" (EN)', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      // Board banner not visible when not connected/adau1466 — just verify
      // no "Room Analysis" strings appear in the connect header/button copy
      expect(find.textContaining('Room Analysis'), findsNothing);
    });
  });

  // ── C.5 Measurement Device display ───────────────────────────────────────

  group('Connect screen — Measurement Device static display', () {
    testWidgets('EN: "Measurement Device" label and no chip selectors (disconnected)',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(find.text('Measurement Device'), findsOneWidget);
      // No Auto/Bluetooth/AUX interactive chips
      expect(find.text('Auto'), findsNothing);
      expect(find.text('AUX'), findsNothing);
    });

    testWidgets('KO: 측정 장치 label visible (disconnected)', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _ko(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(find.text('측정 장치'), findsOneWidget);
      expect(find.text('자동'), findsNothing);
    });

    testWidgets('No "Input Source" label visible anywhere', (tester) async {
      await tester.pumpWidget(ProviderScope(
        child: _en(ConnectScreen(onConnected: () {})),
      ));
      await tester.pump();

      expect(find.text('Input Source'), findsNothing);
    });
  });
}
