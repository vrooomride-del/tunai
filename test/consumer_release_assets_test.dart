import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/features/measure/measure_screen.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ko', 'KR')]) {
    testWidgets(
        'Phone Mic Check status card has no S20-width overflow (${locale.languageCode})',
        (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        locale: locale,
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: PhoneMicCheckStatusLine(
              status:
                  'Galaxy S20 device-specific microphone calibration profile',
            ),
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });
  }

  test('Consumer launcher icon assets use the approved non-PRO source', () {
    final source = File('assets/images/icon.png');
    expect(source.existsSync(), isTrue);
    expect(
      sha256.convert(source.readAsBytesSync()).toString(),
      // OHNUM brand launcher icon (rebrand). Pinned so a wrong/PRO source can
      // never slip in; update deliberately only on an approved brand change.
      'dc84152d1c69f03d17410f85169a922b6337d7857f3f4beb0ec34f25a97cd35d',
    );

    final proSource = File('assets/images/pro_icon_source.png');
    expect(proSource.existsSync(), isTrue);
    expect(
      sha256.convert(proSource.readAsBytesSync()).toString(),
      'a797c5b36f07d86c1af4d20e552692c50c4bd8f8af8063cf187499f8c8a1ace3',
    );

    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        File('android/app/src/main/res/mipmap-$density/ic_launcher.png')
            .existsSync(),
        isTrue,
      );
      expect(
        File('android/app/src/main/res/drawable-$density/'
                'ic_launcher_foreground.png')
            .existsSync(),
        isTrue,
      );
    }
    expect(
      File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml')
          .existsSync(),
      isTrue,
    );
    expect(
      File('ios/Runner/Assets.xcassets/AppIcon.appiconset/'
              'Icon-App-1024x1024@1x.png')
          .existsSync(),
      isTrue,
    );
    expect(
      File('macos/Runner/Assets.xcassets/AppIcon.appiconset/'
              'app_icon_1024.png')
          .existsSync(),
      isTrue,
    );
    for (final webIcon in [
      'web/favicon.png',
      'web/icons/Icon-192.png',
      'web/icons/Icon-512.png',
      'web/icons/Icon-maskable-192.png',
      'web/icons/Icon-maskable-512.png',
    ]) {
      expect(File(webIcon).existsSync(), isTrue);
    }

    final launcherConfig = File('pubspec.yaml').readAsStringSync();
    expect(launcherConfig, contains('image_path: "assets/images/icon.png"'));
    expect(launcherConfig, isNot(contains('consumer_icon_source.png')));
    expect(launcherConfig, isNot(contains('pro_icon_source.png')));
    expect(launcherConfig, contains('image: assets/images/splash_icon.png'));
  });
}
