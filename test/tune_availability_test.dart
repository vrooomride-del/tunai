// Single source of truth for Tune result state — regression coverage for the
// real-device bug where the TUNE screen showed "나만의 사운드가 준비되었습니다"
// / Apply enabled / two graph legends while the actual persisted TunePlan
// for that profile had zero bands, so tapping Apply failed with "적용할
// 조정 내용이 없습니다". Every consumer must derive its decision from
// evaluateTuneAvailability(plan, profile) — never from a proxy signal.

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/room_measurement.dart' show CaptureQualityStatus;
import 'package:tunai/core/tune_availability.dart';
import 'package:tunai/core/tune_plan.dart';

final _created = DateTime.fromMillisecondsSinceEpoch(1000);

ConsumerSoundProfile _profile({
  String tunePlanId = 'plan-1',
  String confidence = 'Medium',
}) =>
    ConsumerSoundProfile(
      id: 'plan-1',
      name: 'Living Room Profile',
      roomType: 'Living Room',
      createdAt: _created,
      updatedAt: _created,
      micProfileName: 'Generic Phone Mic',
      confidence: confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: const [],
      measurementId: 'measurement-1',
      tunePlanId: tunePlanId,
      isSelected: true,
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    );

TunePlan _plan({
  String id = 'plan-1',
  List<TuneCorrectionBand> bands = const [],
}) =>
    TunePlan(
      id: id,
      sourceMeasurementId: 'measurement-1',
      createdAt: _created,
      bands: bands,
      rejectedCandidates: const [],
      safetyBounds: const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: 1,
      warnings: const [],
    );

const _band = TuneCorrectionBand(
  frequencyHz: 120,
  gainDb: -4,
  q: 2,
  evidenceReference: 'measurement-1:peak:120',
  safetyValidated: true,
);

void main() {
  test('non-empty, matching TunePlan + acceptable confidence → readyToApply',
      () {
    final result = evaluateTuneAvailability(
      plan: _plan(bands: const [_band]),
      profile: _profile(),
    );
    expect(result, TuneAvailability.readyToApply);
  });

  test('empty bands on a matching TunePlan → noCorrectionNeeded', () {
    final result = evaluateTuneAvailability(
      plan: _plan(bands: const []),
      profile: _profile(),
    );
    expect(result, TuneAvailability.noCorrectionNeeded);
  });

  test('Low confidence always wins, even with real deployable bands', () {
    final result = evaluateTuneAvailability(
      plan: _plan(bands: const [_band]),
      profile: _profile(confidence: 'Low'),
    );
    expect(result, TuneAvailability.lowConfidence);
  });

  test('no TunePlan at all (TunePlanStore empty/never saved) → lowConfidence, '
      'never readyToApply or noCorrectionNeeded', () {
    final result = evaluateTuneAvailability(
      plan: null,
      profile: _profile(),
    );
    expect(result, TuneAvailability.lowConfidence);
  });

  test(
      'TunePlan exists but belongs to a DIFFERENT profile (TunePlanStore '
      'overwritten by a later Tune generation/Fine Tune save) → '
      'lowConfidence, never a false readyToApply — this is the exact '
      'real-device bug: a stale "ready" profile pointing at a TunePlan that '
      "isn't actually its own", () {
    final result = evaluateTuneAvailability(
      plan: _plan(id: 'plan-DIFFERENT', bands: const [_band]),
      profile: _profile(tunePlanId: 'plan-1'),
    );
    expect(result, TuneAvailability.lowConfidence);
  });
}
