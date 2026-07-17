import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/dsp_state_synchronization.dart';

void main() {
  const request = DspPeqStateRequest(channel: 1, bandId: 0);
  final snapshot = DspStateSnapshot(
    deviceIdentifier: 'speaker-1',
    capturedAt: DateTime.utc(2026, 7, 17),
    peqStates: const [
      DspPeqState(
        channel: 1,
        bandId: 0,
        frequencyHz: 1800,
        gainDb: -1,
        q: 2,
        enabled: true,
      ),
    ],
  );

  DspDeploymentPrerequisiteResult check({
    bool connected = true,
    bool identityValidated = true,
    String expected = 'speaker-1',
    String? actual = 'speaker-1',
    List<DspPeqStateRequest> requests = const [request],
    bool readAvailable = true,
    DspStateSnapshot? state,
  }) =>
      DspDeploymentPrerequisiteCheck.evaluate(
        connected: connected,
        identityValidated: identityValidated,
        expectedDeviceIdentifier: expected,
        actualDeviceIdentifier: actual,
        requiredStates: requests,
        readCapabilityAvailable: readAvailable,
        snapshot: state ?? snapshot,
      );

  test('complete verified snapshot satisfies deployment prerequisites', () {
    expect(check().ready, isTrue);
    expect(snapshot.stateFor(request)?.gainDb, -1);
  });

  test('unavailable read capability blocks without assuming factory state', () {
    final result = check(readAvailable: false);
    expect(result.ready, isFalse);
    expect(result.failure,
        DspDeploymentPrerequisiteFailure.readCapabilityUnavailable);
  });

  test('wrong-device snapshot is rejected', () {
    final other = DspStateSnapshot(
      deviceIdentifier: 'speaker-2',
      capturedAt: DateTime.utc(2026, 7, 17),
      peqStates: snapshot.peqStates,
    );
    final result = check(state: other);
    expect(result.failure,
        DspDeploymentPrerequisiteFailure.snapshotDeviceMismatch);
  });

  test('incomplete snapshot cannot authorize deployment', () {
    final result = check(
      requests: const [
        request,
        DspPeqStateRequest(channel: 1, bandId: 1),
      ],
    );
    expect(result.failure,
        DspDeploymentPrerequisiteFailure.incompleteOrInvalidSnapshot);
  });

  test('connection and identity remain mandatory', () {
    expect(check(connected: false).failure,
        DspDeploymentPrerequisiteFailure.disconnected);
    expect(check(identityValidated: false).failure,
        DspDeploymentPrerequisiteFailure.identityNotValidated);
    expect(check(actual: 'other').failure,
        DspDeploymentPrerequisiteFailure.deviceIdentityMismatch);
  });
}
