import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/sound_preference.dart';
import 'package:tunai/core/tune_outcome_history.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/ai/ai_screen.dart';

final _created = DateTime.fromMillisecondsSinceEpoch(1000);
final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: kDefaultResultCards,
);

ConsumerSoundProfile _profile({
  required bool usedAi,
  String tunePlanId = 'plan-explain',
  int? soundScoreAfter,
}) =>
    ConsumerSoundProfile(
      id: 'plan-explain',
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: _scan.cards,
      preference: SoundPreference.warm,
      usedAiRecommendation: usedAi,
      soundScoreAfter: soundScoreAfter,
      measurementId: 'measurement-explain',
      tunePlanId: tunePlanId,
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    );

// AI Explain only renders on _StateEReadyToApply, which now requires a real,
// non-empty TunePlan matching the profile's tunePlanId (see
// tune_availability.dart) — these tests aren't about TuneAvailability
// branching, so they always provide one.
TunePlan _tunePlan(String id) => TunePlan(
      id: id,
      sourceMeasurementId: 'measurement-explain',
      createdAt: _created,
      bands: const [
        TuneCorrectionBand(
          frequencyHz: 120,
          gainDb: -4,
          q: 2,
          evidenceReference: 'measurement-explain:peak:120',
          safetyValidated: true,
        ),
      ],
      rejectedCandidates: const [],
      safetyBounds: const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: 1,
      warnings: const [],
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

  testWidgets(
      'AI Explain section expands to a plain-language reason with no '
      'technical terms', (tester) async {
    final profiles = ConsumerSoundProfileNotifier();
    await profiles.upsertGeneratedAndSelect(_profile(usedAi: true));
    final scans = RoomScanResultNotifier();
    await scans.saveResult(_scan);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        consumerSoundProfileProvider.overrideWith((ref) => profiles),
        roomScanResultProvider.overrideWith((ref) => scans),
        currentTunePlanProvider
            .overrideWith((ref) async => _tunePlan('plan-explain')),
      ],
      child: _app(AiScreen(onApplied: () {})),
    ));
    await tester.pump();
    await tester.pump();

    final title = find.text('왜 이렇게 만들었나요?');
    expect(title, findsOneWidget);

    await tester.ensureVisible(title);
    await tester.pump();
    await tester.tap(title);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('안전한 범위 안에서'), findsOneWidget);
    expect(find.textContaining('따뜻하게 느낌을 살렸습니다'), findsOneWidget);
    // usedAi: true → the "deeper analysis" line should render.
    expect(find.textContaining('더 깊이 분석했습니다'), findsOneWidget);

    for (final banned in ['DSP', 'PEQ', 'Hz', 'dB', '주파수']) {
      expect(find.textContaining(banned), findsNothing,
          reason: 'banned technical term "$banned" must not be shown');
    }
  });

  testWidgets('AI Explain omits the deeper-analysis line for rule-based Tunes',
      (tester) async {
    final profiles = ConsumerSoundProfileNotifier();
    await profiles.upsertGeneratedAndSelect(_profile(usedAi: false));
    final scans = RoomScanResultNotifier();
    await scans.saveResult(_scan);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        consumerSoundProfileProvider.overrideWith((ref) => profiles),
        roomScanResultProvider.overrideWith((ref) => scans),
        currentTunePlanProvider
            .overrideWith((ref) async => _tunePlan('plan-explain')),
      ],
      child: _app(AiScreen(onApplied: () {})),
    ));
    await tester.pump();
    await tester.pump();

    final title = find.text('왜 이렇게 만들었나요?');
    await tester.ensureVisible(title);
    await tester.pump();
    await tester.tap(title);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('더 깊이 분석했습니다'), findsNothing);
  });

  testWidgets(
      'AI Explain shows a Closed Loop comparison line when a real, lower '
      "prior outcome score exists for a different Tune", (tester) async {
    await TuneOutcomeHistory.record(TuneOutcomeRecord(
      tunePlanId: 'plan-prior',
      measurementId: 'measurement-prior',
      preference: SoundPreference.balanced,
      usedAiRecommendation: false,
      result: ConsumerDspDeploymentRecordResult.applied,
      soundScoreBefore: 50,
      soundScoreAfter: 60,
      recordedAt: DateTime.now(),
    ));
    final profiles = ConsumerSoundProfileNotifier();
    await profiles.upsertGeneratedAndSelect(
        _profile(usedAi: false, soundScoreAfter: 85));
    final scans = RoomScanResultNotifier();
    await scans.saveResult(_scan);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        consumerSoundProfileProvider.overrideWith((ref) => profiles),
        roomScanResultProvider.overrideWith((ref) => scans),
        currentTunePlanProvider
            .overrideWith((ref) async => _tunePlan('plan-explain')),
      ],
      child: _app(AiScreen(onApplied: () {})),
    ));
    await tester.pump();
    await tester.pump();

    final title = find.text('왜 이렇게 만들었나요?');
    await tester.ensureVisible(title);
    await tester.pump();
    await tester.tap(title);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Let the async TuneOutcomeHistory.load() resolve.
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('지난번보다 더 편안한 청취 경험으로 조정되었습니다'),
        findsOneWidget);
  });
}
