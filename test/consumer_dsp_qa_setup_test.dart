import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_dsp_physical_qa_setup.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/tune_plan.dart';

ConsumerSoundProfile _profile({String? tunePlanId}) {
  final now = DateTime.utc(2026, 7, 17);
  return ConsumerSoundProfile(
    id: 'profile-1',
    name: '[DEV QA] Test Profile',
    roomType: 'Living Room',
    createdAt: now,
    updatedAt: now,
    micProfileName: 'Generic Phone Mic',
    confidence: 'Developer QA Simulation',
    isActive: false,
    status: ConsumerProfileStatus.ready,
    resultCards: const [],
    measurementId: 'developer_qa_measurement',
    tunePlanId: tunePlanId,
    isSelected: true,
    generationStatus: ConsumerProfileGenerationStatus.generated,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Run Full Flow setup persists and selects one matching QA pair',
      () async {
    final profiles = ConsumerSoundProfileNotifier();
    final scan = RoomScanResult(
      roomType: 'Living Room',
      micProfileName: 'Generic Phone Mic',
      completedAt: DateTime.utc(2026, 7, 17),
      confidence: 'Medium',
      cards: const [],
    );

    final status = await ConsumerDspPhysicalQaSetup.prepare(
      scan: scan,
      profiles: profiles,
      now: DateTime.utc(2026, 7, 17, 1),
    );
    final storedPlan = await TunePlanStore.load();
    final selected = profiles.selectedProfile;

    expect(storedPlan, isNotNull);
    expect(storedPlan!.id, startsWith('developer_qa_tune_plan_'));
    expect(storedPlan.warnings,
        contains('DEVELOPER_QA_SIMULATION_DATA_NOT_PHYSICAL_MEASUREMENT'));
    expect(selected, isNotNull);
    expect(selected!.name, '[DEV QA] Physical ICP5 Harness');
    expect(selected.tunePlanId, storedPlan.id);
    expect(status.matches, isTrue);
    expect(status.blockReason, 'none');

    // Existing simulation lifecycle activates the already selected profile.
    await profiles.setActive(selected.id);
    expect(profiles.selectedProfile?.isActive, isTrue);
  });

  test('provider reload preserves selected profile and TunePlan match',
      () async {
    final first = ConsumerSoundProfileNotifier();
    await ConsumerDspPhysicalQaSetup.prepare(
      scan: RoomScanResult(
        roomType: 'Desk',
        micProfileName: 'Generic Phone Mic',
        completedAt: DateTime.utc(2026, 7, 17),
        confidence: 'Medium',
        cards: const [],
      ),
      profiles: first,
      now: DateTime.utc(2026, 7, 17, 2),
    );

    final reloadedProfiles = ConsumerSoundProfileNotifier();
    await reloadedProfiles.reload();
    final status = ConsumerDspQaPairStatus.evaluate(
      storedTunePlan: await TunePlanStore.load(),
      selectedProfile: reloadedProfiles.selectedProfile,
    );

    expect(status.matches, isTrue);
    expect(status.selectedProfileTunePlanId, status.storedTunePlanId);
  });

  test('mismatched selected profile remains blocked', () {
    final status = ConsumerDspQaPairStatus.evaluate(
      storedTunePlan: TunePlan(
        id: 'stored-plan',
        sourceMeasurementId: 'developer_qa_measurement',
        createdAt: DateTime.utc(2026),
        bands: const [],
        rejectedCandidates: const [],
        safetyBounds: const TuneSafetyBounds(),
        measurementQuality: CaptureQualityStatus.valid,
        measurementConsistency: 1,
        warnings: const [],
      ),
      selectedProfile: _profile(tunePlanId: 'other-plan'),
    );
    expect(status.matches, isFalse);
    expect(status.blockReason, 'tunePlanMismatch');
  });

  test('missing TunePlan remains blocked', () {
    final status = ConsumerDspQaPairStatus.evaluate(
      storedTunePlan: null,
      selectedProfile: _profile(tunePlanId: 'plan-1'),
    );
    expect(status.matches, isFalse);
    expect(status.blockReason, 'missingTunePlan');
  });

  test('normal Consumer Tune flow is not wired to developer QA setup', () {
    final source = File('lib/features/ai/ai_screen.dart').readAsStringSync();
    expect(source, contains('TunePlanner'));
    expect(source, contains('upsertGeneratedAndSelect'));
    expect(source, isNot(contains('ConsumerDspPhysicalQaSetup')));
  });

  test('developer QA setup contains no BLE transport or physical write', () {
    final source =
        File('lib/core/consumer_dsp_physical_qa_setup.dart').readAsStringSync();
    expect(source, isNot(contains('ConsumerBle')));
    expect(source, isNot(contains('writeAndAwait')));
  });
}
