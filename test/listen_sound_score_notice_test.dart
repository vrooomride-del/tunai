// LISTEN must never repeat the "72 → 72, +0" bug that TUNE's result screen
// already avoids — an active profile whose score didn't genuinely improve
// should read as "balance maintained", not a flat non-improvement number.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/listen/listen_screen.dart';

final _created = DateTime.fromMillisecondsSinceEpoch(1000);
final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: kDefaultResultCards,
);

ConsumerSoundProfile _activeProfile({int? before, int? after}) =>
    ConsumerSoundProfile(
      id: 'listen-score',
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: true,
      status: ConsumerProfileStatus.active,
      resultCards: _scan.cards,
      soundScoreBefore: before,
      soundScoreAfter: after,
      deploymentStatus: TuneDeploymentStatus.applied,
    );

Widget _app(Widget child) => MaterialApp(
      locale: const Locale('ko'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ko')],
      home: child,
    );

Future<void> _pump(WidgetTester tester, ConsumerSoundProfile profile) async {
  final notifier = ConsumerSoundProfileNotifier();
  await notifier.upsertAndActivate(profile);
  await tester.pumpWidget(ProviderScope(
    overrides: [consumerSoundProfileProvider.overrideWith((ref) => notifier)],
    child: _app(const ListenScreen()),
  ));
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('genuine improvement shows the real Sound Score numbers',
      (tester) async {
    await _pump(tester, _activeProfile(before: 60, after: 78));

    expect(find.text('Sound Score'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    expect(find.textContaining('자연스러운 균형을 유지했습니다'), findsNothing);
  });

  testWidgets('no improvement shows "balance maintained", never "X → X, +0"',
      (tester) async {
    await _pump(tester, _activeProfile(before: 72, after: 72));

    expect(find.text('Sound Score'), findsNothing);
    expect(find.text('+0'), findsNothing);
    expect(find.textContaining('자연스러운 균형을 유지했습니다'), findsOneWidget);
  });

  // "Listening Level" (낮게/편안하게/생생하게) was removed: it was a raw
  // Master Volume slider (MasterVolumeController.setVolume →
  // kAdau1701MasterVolL/R gain write) mislabeled as a "sound character"
  // picker — the only real Sound Character change Consumer offers is the
  // Original/TUNAI toggle, which actually switches the EQ curve.
  testWidgets('Listening Level volume section is gone from LISTEN', (tester) async {
    await _pump(tester, _activeProfile());

    expect(find.text('Listening Level'), findsNothing);
    expect(find.text('듣기 음량'), findsNothing);
    expect(find.textContaining('Master Volume'), findsNothing);
    expect(find.text('Low'), findsNothing);
    expect(find.text('Comfortable'), findsNothing);
    expect(find.text('Lively'), findsNothing);
  });
}
