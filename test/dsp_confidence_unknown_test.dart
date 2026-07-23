// Regression test for the real-device bug where the Room Balance graph
// silently vanished from TUNE right after a BLE disconnect: any disconnect
// (even one auto-reconnect immediately recovered from) called
// markCurrentDspConfidenceUnknown(), which used to flip EVERY profile's
// deploymentStatus to `unknown` — including a Tune that had never been
// applied at all. That knocked it out of ai_screen.dart's `ready` filter
// (which requires deploymentStatus == notDeployed), silently falling the
// TUNE screen back to "no profile yet" and dropping the graph with it, even
// though nothing about the Tune's own correctness was ever in question.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_scan_result.dart';
import 'package:tunai/core/tune_plan.dart';

final _created = DateTime.fromMillisecondsSinceEpoch(1000);
final _scan = RoomScanResult(
  roomType: 'Living Room',
  micProfileName: 'Generic Phone Mic',
  completedAt: _created,
  confidence: 'Medium',
  cards: kDefaultResultCards,
);

ConsumerSoundProfile _profile({
  required String id,
  required TuneDeploymentStatus deploymentStatus,
}) =>
    ConsumerSoundProfile(
      id: id,
      name: 'Living Room Profile',
      roomType: _scan.roomType,
      createdAt: _created,
      updatedAt: _created,
      micProfileName: _scan.micProfileName,
      confidence: _scan.confidence,
      isActive: deploymentStatus == TuneDeploymentStatus.applied,
      status: deploymentStatus == TuneDeploymentStatus.applied
          ? ConsumerProfileStatus.active
          : ConsumerProfileStatus.ready,
      resultCards: _scan.cards,
      measurementId: 'measurement-$id',
      tunePlanId: id,
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: deploymentStatus,
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'a never-applied (notDeployed) Tune survives a BLE disconnect — stays '
      'notDeployed, never demoted to unknown', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.upsertGeneratedAndSelect(
        _profile(id: 'tune-fresh', deploymentStatus: TuneDeploymentStatus.notDeployed));

    await notifier.markCurrentDspConfidenceUnknown();

    final updated = notifier.state.firstWhere((p) => p.id == 'tune-fresh');
    expect(updated.deploymentStatus, TuneDeploymentStatus.notDeployed,
        reason: 'nothing was ever written to the device for this profile, '
            'so a disconnect creates no new uncertainty about it');
  });

  test(
      'an actually-applied Tune IS demoted to unknown on disconnect — the '
      'device state genuinely became unverifiable', () async {
    final notifier = ConsumerSoundProfileNotifier();
    // upsertAndActivate (unlike upsertGeneratedAndSelect) preserves the
    // passed-in deploymentStatus — the right fixture path for an
    // already-applied profile.
    await notifier.upsertAndActivate(
        _profile(id: 'tune-applied', deploymentStatus: TuneDeploymentStatus.applied));

    await notifier.markCurrentDspConfidenceUnknown();

    final updated = notifier.state.firstWhere((p) => p.id == 'tune-applied');
    expect(updated.deploymentStatus, TuneDeploymentStatus.unknown);
  });

  test(
      'a mid-write (deploying) Tune is also demoted — an interrupted write '
      'is genuinely uncertain', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.upsertAndActivate(
        _profile(id: 'tune-mid', deploymentStatus: TuneDeploymentStatus.deploying));

    await notifier.markCurrentDspConfidenceUnknown();

    final updated = notifier.state.firstWhere((p) => p.id == 'tune-mid');
    expect(updated.deploymentStatus, TuneDeploymentStatus.unknown);
  });

  test(
      'mixed profiles: only the applied one is demoted, the notDeployed one '
      'is untouched — confirms this is per-profile, not global', () async {
    final notifier = ConsumerSoundProfileNotifier();
    await notifier.upsertAndActivate(
        _profile(id: 'tune-applied', deploymentStatus: TuneDeploymentStatus.applied));
    await notifier.upsertGeneratedAndSelect(
        _profile(id: 'tune-fresh', deploymentStatus: TuneDeploymentStatus.notDeployed));

    await notifier.markCurrentDspConfidenceUnknown();

    final applied = notifier.state.firstWhere((p) => p.id == 'tune-applied');
    final fresh = notifier.state.firstWhere((p) => p.id == 'tune-fresh');
    expect(applied.deploymentStatus, TuneDeploymentStatus.unknown);
    expect(fresh.deploymentStatus, TuneDeploymentStatus.notDeployed);
  });
}
