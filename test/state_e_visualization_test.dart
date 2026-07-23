// Room Scan result Visualization — Room Balance chart must appear on the
// TUNE result screen (State E, ready-to-apply) whenever a real measured
// curve exists, using only already-computed data from spectrumSnapshotProvider
// (never a new measurement/analysis). No graph is fabricated when there's
// no real snapshot for the session.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/audio_analyzer.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/spectrum_snapshot.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/ai/ai_screen.dart';
import 'package:tunai/shared/consumer_response_chart.dart';

final _created = DateTime.fromMillisecondsSinceEpoch(1000);
final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: kDefaultResultCards,
);

ConsumerSoundProfile _readyProfile() => ConsumerSoundProfile(
      id: 'plan-viz',
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: _scan.cards,
      measurementId: 'measurement-viz',
      tunePlanId: 'plan-viz',
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    );

// _StateEReadyToApply now requires a real, non-empty TunePlan matching the
// profile's tunePlanId (tune_availability.dart) — provide one so these
// tests reach the branch they're actually about.
final _readyTunePlan = TunePlan(
  id: 'plan-viz',
  sourceMeasurementId: 'measurement-viz',
  createdAt: _created,
  bands: const [
    TuneCorrectionBand(
      frequencyHz: 120,
      gainDb: -4,
      q: 2,
      evidenceReference: 'measurement-viz:peak:120',
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

Future<void> _pumpState(
  WidgetTester tester, {
  required SpectrumSnapshotController snapshot,
}) async {
  final profiles = ConsumerSoundProfileNotifier();
  await profiles.upsertGeneratedAndSelect(_readyProfile());
  final scans = RoomScanResultNotifier();
  await scans.saveResult(_scan);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      consumerSoundProfileProvider.overrideWith((ref) => profiles),
      roomScanResultProvider.overrideWith((ref) => scans),
      spectrumSnapshotProvider.overrideWith((ref) => snapshot),
      currentTunePlanProvider.overrideWith((ref) async => _readyTunePlan),
    ],
    child: _app(AiScreen(onApplied: () {})),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows Room Balance chart with both curves when a real '
      'before/after snapshot exists', (tester) async {
    final snapshot = SpectrumSnapshotController();
    snapshot.setBefore(const [
      FrequencyBin(frequency: 60, magnitude: -14),
      FrequencyBin(frequency: 120, magnitude: -6),
      FrequencyBin(frequency: 250, magnitude: -10),
    ]);
    snapshot.applyPeaks(
        const [ResonancePeak(frequency: 120, gain: -4, q: 2)]);

    await _pumpState(tester, snapshot: snapshot);

    expect(find.text('Room Balance'), findsOneWidget);
    expect(find.byType(ConsumerResponseChart), findsOneWidget);
    expect(find.text('TUNAI 예상 균형'), findsOneWidget);
  });

  testWidgets('shows only the Before curve when no TunePlan-derived after '
      'curve was synthesized', (tester) async {
    final snapshot = SpectrumSnapshotController();
    snapshot.setBefore(const [
      FrequencyBin(frequency: 60, magnitude: -14),
      FrequencyBin(frequency: 120, magnitude: -6),
    ]);

    await _pumpState(tester, snapshot: snapshot);

    expect(find.text('Room Balance'), findsOneWidget);
    expect(find.byType(ConsumerResponseChart), findsOneWidget);
    expect(find.text('TUNAI 예상 균형'), findsNothing);
  });

  testWidgets('shows no chart at all when there is no real snapshot for '
      'this session (never a fabricated graph)', (tester) async {
    await _pumpState(tester, snapshot: SpectrumSnapshotController());

    expect(find.text('Room Balance'), findsNothing);
    expect(find.byType(ConsumerResponseChart), findsNothing);
  });
}
