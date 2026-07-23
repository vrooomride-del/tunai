import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/sound_preference.dart';
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

ConsumerSoundProfile _profile({int? before, int? after}) => ConsumerSoundProfile(
      id: 'plan-score',
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: _scan.cards,
      preference: SoundPreference.balanced,
      soundScoreBefore: before,
      soundScoreAfter: after,
      measurementId: 'measurement-score',
      tunePlanId: 'plan-score',
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    );

// _StateEReadyToApply (where the Sound Score card / _NoImprovementNotice
// renders) now requires a real, non-empty TunePlan matching the profile's
// tunePlanId (tune_availability.dart).
final _readyTunePlan = TunePlan(
  id: 'plan-score',
  sourceMeasurementId: 'measurement-score',
  createdAt: _created,
  bands: const [
    TuneCorrectionBand(
      frequencyHz: 120,
      gainDb: -4,
      q: 2,
      evidenceReference: 'measurement-score:peak:120',
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

Future<void> _pumpState(WidgetTester tester, ConsumerSoundProfile profile) async {
  final profiles = ConsumerSoundProfileNotifier();
  await profiles.upsertGeneratedAndSelect(profile);
  final scans = RoomScanResultNotifier();
  await scans.saveResult(_scan);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      consumerSoundProfileProvider.overrideWith((ref) => profiles),
      roomScanResultProvider.overrideWith((ref) => scans),
      currentTunePlanProvider.overrideWith((ref) async => _readyTunePlan),
    ],
    child: _app(AiScreen(onApplied: () {})),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'shows the real Sound Score card when there is a genuine improvement',
      (tester) async {
    await _pumpState(tester, _profile(before: 60, after: 78));

    expect(find.text('Sound Score'), findsOneWidget);
    expect(find.text('60'), findsOneWidget);
    expect(find.text('78'), findsOneWidget);
    expect(find.textContaining('자연스러운 균형을 유지했습니다'), findsNothing);
  });

  testWidgets(
      'shows an honest "no improvement found" notice instead of "X → X, +0" '
      'when the score did not improve', (tester) async {
    await _pumpState(tester, _profile(before: 72, after: 72));

    // The literal "72 → 72, +0" reading is never shown as a result card.
    expect(find.text('Sound Score'), findsNothing);
    expect(find.textContaining('자연스러운 균형을 유지했습니다'), findsOneWidget);
  });

  testWidgets('handles a decreased score the same honest way (never negative "improvement")',
      (tester) async {
    await _pumpState(tester, _profile(before: 80, after: 75));

    expect(find.text('Sound Score'), findsNothing);
    expect(find.textContaining('자연스러운 균형을 유지했습니다'), findsOneWidget);
  });
}
