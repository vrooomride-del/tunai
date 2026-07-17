import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/features/onboarding/onboarding_screen.dart';
import 'package:tunai/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('fresh launch advances through all three approved screens',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(onComplete: () => completed = true),
    ));

    expect(find.text('Your room shapes your sound.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create your personal sound.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Connect. Analyze. Enjoy.'), findsOneWidget);
    await tester.tap(find.text('Get Started'));
    await tester.pumpAndSettle();

    expect(completed, isTrue);
    expect(await isOnboardingComplete(), isTrue);
  });

  testWidgets('completion enters app and subsequent launch skips onboarding',
      (tester) async {
    await markOnboardingComplete();
    await tester.pumpWidget(const ProviderScope(child: TunaiApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your room shapes your sound.'), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('Korean onboarding keeps all three localized screens',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ko', 'KR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko')],
      home: OnboardingScreen(onComplete: () {}),
    ));
    expect(find.text('당신의 공간이 소리를 만듭니다.'), findsOneWidget);
    expect(find.textContaining('같은 스피커도 공간에 따라'), findsOneWidget);
    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();
    expect(find.text('당신만의 사운드를 만드세요.'), findsOneWidget);
    expect(find.textContaining('AI Acoustic Intelligence가'), findsOneWidget);
    await tester.tap(find.text('계속'));
    await tester.pumpAndSettle();
    expect(find.text('연결하고, 분석하고, 경험하세요.'), findsOneWidget);
    expect(find.textContaining('TUNAI 스피커를 연결하고'), findsOneWidget);
  });

  testWidgets('cleared completion state restores the three-screen sequence',
      (tester) async {
    await markOnboardingComplete();
    SharedPreferences.setMockInitialValues({});
    expect(await isOnboardingComplete(), isFalse);

    await tester.pumpWidget(const ProviderScope(child: TunaiApp()));
    await tester.pumpAndSettle();
    expect(find.text('Your room shapes your sound.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Create your personal sound.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Connect. Analyze. Enjoy.'), findsOneWidget);
  });
}
