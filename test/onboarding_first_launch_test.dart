import 'package:flutter/material.dart';
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

    expect(find.text('The audio paradigm is changing.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Space changes.\nPlacement changes.\nTaste changes.'),
        findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('The controls disappear.\nThe sound remains.'),
        findsOneWidget);
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
    expect(find.text('The audio paradigm is changing.'), findsNothing);
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });

  testWidgets('cleared completion state restores the three-screen sequence',
      (tester) async {
    await markOnboardingComplete();
    SharedPreferences.setMockInitialValues({});
    expect(await isOnboardingComplete(), isFalse);

    await tester.pumpWidget(const ProviderScope(child: TunaiApp()));
    await tester.pumpAndSettle();
    expect(find.text('The audio paradigm is changing.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Space changes.\nPlacement changes.\nTaste changes.'),
        findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('The controls disappear.\nThe sound remains.'),
        findsOneWidget);
  });
}
