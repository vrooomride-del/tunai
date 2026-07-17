import 'consumer_sound_profile.dart';
import 'room_measurement.dart';
import 'room_scan_result.dart';
import 'tune_plan.dart';

class ConsumerDspQaPairStatus {
  final String? storedTunePlanId;
  final String? selectedProfileId;
  final String? selectedProfileTunePlanId;
  final bool matches;
  final String blockReason;

  const ConsumerDspQaPairStatus({
    required this.storedTunePlanId,
    required this.selectedProfileId,
    required this.selectedProfileTunePlanId,
    required this.matches,
    required this.blockReason,
  });

  factory ConsumerDspQaPairStatus.evaluate({
    required TunePlan? storedTunePlan,
    required ConsumerSoundProfile? selectedProfile,
  }) {
    final reason = storedTunePlan == null
        ? 'missingTunePlan'
        : selectedProfile == null
            ? 'missingSelectedProfile'
            : selectedProfile.tunePlanId == null
                ? 'selectedProfileMissingTunePlanId'
                : selectedProfile.tunePlanId != storedTunePlan.id
                    ? 'tunePlanMismatch'
                    : 'none';
    return ConsumerDspQaPairStatus(
      storedTunePlanId: storedTunePlan?.id,
      selectedProfileId: selectedProfile?.id,
      selectedProfileTunePlanId: selectedProfile?.tunePlanId,
      matches: reason == 'none',
      blockReason: reason,
    );
  }
}

/// Creates developer-only persistence objects for the physical QA harness.
/// These records are explicitly labelled simulation data and are never used by
/// the normal measurement/TunePlan generation flow.
abstract final class ConsumerDspPhysicalQaSetup {
  static Future<ConsumerDspQaPairStatus> prepare({
    required RoomScanResult scan,
    required ConsumerSoundProfileNotifier profiles,
    required DateTime now,
  }) async {
    final token = now.toUtc().microsecondsSinceEpoch;
    final measurementId = 'developer_qa_simulated_measurement_$token';
    final plan = TunePlan(
      id: 'developer_qa_tune_plan_$token',
      sourceMeasurementId: measurementId,
      createdAt: now.toUtc(),
      bands: const [
        TuneCorrectionBand(
          frequencyHz: 180,
          gainDb: -1,
          q: 2,
          evidenceReference: 'developer_qa_simulation:not_physical_measurement',
          safetyValidated: true,
        ),
      ],
      rejectedCandidates: const [],
      safetyBounds: const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.invalid,
      measurementConsistency: 0,
      warnings: const [
        'DEVELOPER_QA_SIMULATION_DATA_NOT_PHYSICAL_MEASUREMENT',
      ],
    );
    await TunePlanStore.save(plan);

    final profile = ConsumerSoundProfile(
      id: 'developer_qa_profile_$token',
      name: '[DEV QA] Physical ICP5 Harness',
      roomType: scan.roomType,
      createdAt: now,
      updatedAt: now,
      micProfileName: scan.micProfileName,
      confidence: 'Developer QA Simulation',
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: scan.cards,
      profileType: ConsumerProfileType.tunaiTune,
      measurementId: measurementId,
      tunePlanId: plan.id,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    );
    await profiles.upsertGeneratedAndSelect(profile);

    // Verify persisted truth, not just the objects passed to save/upsert.
    await profiles.reload();
    final reloadedPlan = await TunePlanStore.load();
    final selected = profiles.selectedProfile;
    return ConsumerDspQaPairStatus.evaluate(
      storedTunePlan: reloadedPlan,
      selectedProfile: selected,
    );
  }
}
