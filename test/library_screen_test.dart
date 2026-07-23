import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_outcome_history.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/library/library_screen.dart';

final _created = DateTime.utc(2026, 7, 21);

ConsumerSoundProfile _profile({
  required String id,
  required String roomType,
  bool isSelected = true,
}) =>
    ConsumerSoundProfile(
      id: id,
      name: '$roomType Your Sound',
      roomType: roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: 'Generic Phone Mic',
      confidence: 'High',
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: const [],
      profileType: ConsumerProfileType.tunaiTune,
      measurementId: 'measurement-$id',
      tunePlanId: 'plan-$id',
      isSelected: isSelected,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('groups TUNAI Tune profiles by room when there are multiple rooms',
      (tester) async {
    final profiles = ConsumerSoundProfileNotifier();
    await profiles.add(_profile(id: 'living', roomType: 'Living Room'));
    await profiles.add(_profile(id: 'desk', roomType: 'Desk'));

    await tester.pumpWidget(ProviderScope(
      overrides: [consumerSoundProfileProvider.overrideWith((ref) => profiles)],
      child: _app(const LibraryScreen()),
    ));
    await tester.pump();

    // "거실"/"책상 위" also appear in each card's meta chip, so assert on the
    // room sub-header icon (unique to the grouping headers) instead.
    expect(find.byIcon(Icons.room_outlined), findsNWidgets(2));
    expect(find.text('거실'), findsWidgets);
    expect(find.text('책상 위'), findsWidgets);
  });

  testWidgets('does not show room sub-headers when there is only one room',
      (tester) async {
    final profiles = ConsumerSoundProfileNotifier();
    await profiles.add(_profile(id: 'a', roomType: 'Living Room'));
    await profiles.add(_profile(id: 'b', roomType: 'Living Room'));

    await tester.pumpWidget(ProviderScope(
      overrides: [consumerSoundProfileProvider.overrideWith((ref) => profiles)],
      child: _app(const LibraryScreen()),
    ));
    await tester.pump();

    expect(find.byIcon(Icons.room_outlined), findsNothing);
  });

  testWidgets(
      'shows Recent Activity with real outcome data, in plain language, '
      'no technical terms', (tester) async {
    await TuneOutcomeHistory.record(TuneOutcomeRecord(
      tunePlanId: 'plan-history-1',
      measurementId: 'measurement-history-1',
      preference: SoundPreference.warm,
      usedAiRecommendation: true,
      result: ConsumerDspDeploymentRecordResult.applied,
      soundScoreBefore: 60,
      soundScoreAfter: 82,
      recordedAt: DateTime.now(),
    ));
    final profiles = ConsumerSoundProfileNotifier();

    await tester.pumpWidget(ProviderScope(
      overrides: [consumerSoundProfileProvider.overrideWith((ref) => profiles)],
      child: _app(const LibraryScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('최근 기록'), findsOneWidget);
    expect(find.textContaining('더 편안한 청취 경험으로 조정되었습니다'), findsOneWidget);
    expect(find.textContaining('오늘'), findsOneWidget);

    for (final banned in ['DSP', 'PEQ', 'Hz', 'dB', '주파수']) {
      expect(find.textContaining(banned), findsNothing,
          reason: 'banned technical term "$banned" must not be shown');
    }
  });

  testWidgets('Recent Activity is absent when there is no history yet',
      (tester) async {
    final profiles = ConsumerSoundProfileNotifier();

    await tester.pumpWidget(ProviderScope(
      overrides: [consumerSoundProfileProvider.overrideWith((ref) => profiles)],
      child: _app(const LibraryScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('최근 기록'), findsNothing);
  });
}
