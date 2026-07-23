// Tests for State E's 3-way branch (real correction / balanced / low
// confidence) so a "no correction found" result never dead-ends the Flow and
// never reads as a failure — the user must always get a real next action and
// an honest explanation of what TUNAI actually checked.

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

const _neutralCard = RoomScanResultCard(
  id: 'measured_neutral',
  labelEn: 'Space Analysis',
  labelKo: '공간 스캔',
  descriptionEn: 'no buildup found',
  descriptionKo: '부풀림 없음',
  evidenceKey: 'no_bounded_peak_20_500hz',
);

RoomScanResult _scan({required String confidence}) => RoomScanResult(
      roomType: 'Living Room',
      micProfileName: 'Generic Phone Mic',
      completedAt: _created,
      confidence: confidence,
      cards: const [_neutralCard],
    );

ConsumerSoundProfile _noCorrectionProfile({required String confidence}) =>
    ConsumerSoundProfile(
      id: 'plan-no-correction',
      name: 'Living Room Profile',
      roomType: 'Living Room',
      createdAt: _created,
      updatedAt: _created,
      micProfileName: 'Generic Phone Mic',
      confidence: confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: const [_neutralCard],
      preference: SoundPreference.balanced,
      measurementId: 'measurement-no-correction',
      tunePlanId: 'plan-no-correction',
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    );

// TuneAvailability.noCorrectionNeeded now requires a real, matching TunePlan
// with zero bands (see tune_availability.dart) — not just a resultCards
// proxy — so these fixtures provide one explicitly.
final _emptyTunePlan = TunePlan(
  id: 'plan-no-correction',
  sourceMeasurementId: 'measurement-no-correction',
  createdAt: _created,
  bands: const [],
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

Future<ConsumerSoundProfileNotifier> _pumpState(
  WidgetTester tester, {
  required String confidence,
  void Function(int)? onGoTo,
}) async {
  final profiles = ConsumerSoundProfileNotifier();
  await profiles.upsertGeneratedAndSelect(_noCorrectionProfile(confidence: confidence));
  final scans = RoomScanResultNotifier();
  await scans.saveResult(_scan(confidence: confidence));

  await tester.pumpWidget(ProviderScope(
    overrides: [
      consumerSoundProfileProvider.overrideWith((ref) => profiles),
      roomScanResultProvider.overrideWith((ref) => scans),
      currentTunePlanProvider.overrideWith((ref) async => _emptyTunePlan),
    ],
    child: _app(AiScreen(onApplied: () {}, onGoTo: onGoTo)),
  ));
  await tester.pump();
  await tester.pump();
  return profiles;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('no correction found (Medium confidence) shows "already balanced" '
      'with Done + Measure-again, never a dead Apply button', (tester) async {
    await _pumpState(tester, confidence: 'Medium');

    expect(find.textContaining('공간 분석이 완료되었습니다'), findsOneWidget);
    expect(find.text('완료'), findsOneWidget);
    expect(find.text('다시 측정하기'), findsOneWidget);
    // Real analysis facts are shown, not a blank/failure result.
    expect(find.text('공간 균형'), findsOneWidget);
    expect(find.text('저음 응답'), findsOneWidget);
    expect(find.text('측정 신뢰도'), findsOneWidget);
    // The old always-visible Apply button must not appear in this branch.
    expect(find.text('스피커에 적용'), findsNothing);
    expect(find.text('스피커 확인 필요'), findsNothing);
  });

  testWidgets('no correction found (Low confidence) shows the low-confidence '
      'explanation with an immediate re-measure action', (tester) async {
    await _pumpState(tester, confidence: 'Low');

    expect(find.textContaining('측정 신뢰도가 부족합니다'), findsOneWidget);
    expect(find.text('다시 측정하기'), findsOneWidget);
    expect(find.text('완료'), findsNothing);
  });

  testWidgets('tapping Done marks the profile draft (never active, never a '
      'fake applied state)', (tester) async {
    final profiles = await _pumpState(tester, confidence: 'Medium');

    await tester.tap(find.text('완료'));
    await tester.pump();

    final updated = profiles.state.firstWhere((p) => p.id == 'plan-no-correction');
    expect(updated.status, ConsumerProfileStatus.draft);
    expect(updated.isActive, isFalse);
  });

  testWidgets('tapping "다시 측정하기" resets measurement state and navigates to '
      'the ROOM tab', (tester) async {
    int? goToIndex;

    await _pumpState(
      tester,
      confidence: 'Medium',
      onGoTo: (i) => goToIndex = i,
    );

    await tester.tap(find.text('다시 측정하기'));
    await tester.pump();

    expect(goToIndex, 1);
  });
}
