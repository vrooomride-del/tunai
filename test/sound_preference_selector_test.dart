import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/features/ai/ai_screen.dart';

final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: DateTime.fromMillisecondsSinceEpoch(1000),
  confidence: 'Medium',
  cards: kDefaultResultCards,
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('all five preference labels are shown, no technical terms',
      (tester) async {
    final scanNotifier = RoomScanResultNotifier();
    await scanNotifier.saveResult(_scan);
    await tester.pumpWidget(ProviderScope(
      overrides: [roomScanResultProvider.overrideWith((ref) => scanNotifier)],
      child: _app(AiScreen(onApplied: () {})),
    ));
    await tester.pump();

    for (final preference in SoundPreference.values) {
      expect(find.text(preference.label(ko: false)), findsOneWidget);
    }
    expect(find.textContaining('PEQ'), findsNothing);
    expect(find.textContaining('DSP'), findsNothing);
    expect(find.textContaining('dB'), findsNothing);
  });

  testWidgets('tapping a preference chip updates the selection',
      (tester) async {
    final scanNotifier = RoomScanResultNotifier();
    await scanNotifier.saveResult(_scan);
    final container = ProviderContainer(overrides: [
      roomScanResultProvider.overrideWith((ref) => scanNotifier),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: _app(AiScreen(onApplied: () {})),
    ));
    await tester.pump();

    expect(container.read(soundPreferenceProvider), SoundPreference.balanced);

    await tester.tap(find.text(SoundPreference.warm.label(ko: false)));
    await tester.pump();

    expect(container.read(soundPreferenceProvider), SoundPreference.warm);
  });

  testWidgets('KO: preference labels render in Korean', (tester) async {
    final scanNotifier = RoomScanResultNotifier();
    await scanNotifier.saveResult(_scan);
    await tester.pumpWidget(ProviderScope(
      overrides: [roomScanResultProvider.overrideWith((ref) => scanNotifier)],
      child: _app(AiScreen(onApplied: () {}), locale: const Locale('ko')),
    ));
    await tester.pump();

    expect(find.text(SoundPreference.warm.label(ko: true)), findsOneWidget);
    expect(find.text(SoundPreference.vocal.label(ko: true)), findsOneWidget);
  });
}
