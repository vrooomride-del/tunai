import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/features/splash/brand_identity.dart';
import 'package:tunai/features/splash/splash_screen.dart';

void main() {
  group('SplashScreen', () {
    testWidgets('does not finish before the minimum duration elapses',
        (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          onFinished: () => finished = true,
          minDuration: const Duration(milliseconds: 400),
          playLogoSound: false,
        ),
      ));

      await tester.pump(const Duration(milliseconds: 200));
      expect(finished, isFalse);
    });

    testWidgets('finishes exactly once after the animation completes',
        (tester) async {
      var finishedCount = 0;
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          onFinished: () => finishedCount++,
          minDuration: const Duration(milliseconds: 400),
          playLogoSound: false,
        ),
      ));

      await tester.pumpAndSettle();
      expect(finishedCount, 1);

      // Extra pumps must not trigger a second call.
      await tester.pump(const Duration(seconds: 1));
      expect(finishedCount, 1);
    });

    testWidgets(
        'missing/failing logo sound asset does not block completion or throw',
        (tester) async {
      var finished = false;
      const minDuration = Duration(milliseconds: 300);
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          onFinished: () => finished = true,
          minDuration: minDuration,
          // just_audio has no real platform channel in the widget test
          // harness. The platform call can hang rather than reject quickly,
          // so completion here only comes from the fail-safe (2x
          // minDuration) — this must never throw, and must eventually
          // finish rather than hang forever.
          playLogoSound: true,
        ),
      ));

      // Advance past the animation AND the fail-safe ceiling explicitly —
      // pumpAndSettle() alone won't advance a pending Timer once nothing is
      // requesting new frames.
      await tester.pump(minDuration * 2 + const Duration(milliseconds: 50));
      expect(finished, isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('replaces the route so Splash is not part of the back stack',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => SplashScreen(
            onFinished: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('NEXT')),
                ),
              );
            },
            minDuration: const Duration(milliseconds: 300),
            playLogoSound: false,
          ),
        ),
      ));

      await tester.pumpAndSettle();
      expect(find.text('NEXT'), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
    });

    testWidgets('disposing before completion cancels callbacks cleanly',
        (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          onFinished: () => finished = true,
          minDuration: const Duration(milliseconds: 2000),
          playLogoSound: false,
        ),
      ));

      await tester.pump(const Duration(milliseconds: 100));
      // Replace the widget tree before the splash would naturally finish.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 3));

      expect(finished, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion renders without throwing', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SplashScreen(
            onFinished: () {},
            minDuration: const Duration(milliseconds: 300),
            playLogoSound: false,
          ),
        ),
      ));

      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    });
  });

  group('SplashScreen brand identity', () {
    testWidgets('renders the default brand image asset', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          onFinished: () {},
          minDuration: const Duration(milliseconds: 300),
          playLogoSound: false,
        ),
      ));
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName,
          BrandIdentity.tunai.imageAssetPath);
    });

    testWidgets(
        'swapping BrandIdentity renders a different image asset with no code change',
        (tester) async {
      // Uses a real, already-bundled asset (not the brand's own splash_bi.png)
      // purely to prove the image path is driven by BrandIdentity with no
      // code change — same reasoning as the real "swap the wordmark" intent
      // this test previously covered.
      const otherBrand = BrandIdentity(
        name: 'OHNM',
        logoSoundAssetPath: 'assets/audio/ohnm_logo_sound.wav',
        imageAssetPath: 'assets/images/icon.png',
      );
      await tester.pumpWidget(MaterialApp(
        home: SplashScreen(
          onFinished: () {},
          minDuration: const Duration(milliseconds: 300),
          playLogoSound: false,
          brand: otherBrand,
        ),
      ));
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as AssetImage).assetName, 'assets/images/icon.png');
      expect((image.image as AssetImage).assetName,
          isNot(BrandIdentity.tunai.imageAssetPath));
    });
  });
}
