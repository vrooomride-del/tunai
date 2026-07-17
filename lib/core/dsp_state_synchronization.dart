/// Hardware-neutral identity for one parametric equalizer band.
///
/// This is state read from a device, not a requested correction and not a
/// factory-default assumption.
class DspPeqState {
  final int channel;
  final int bandId;
  final int frequencyHz;
  final double gainDb;
  final double q;
  final bool enabled;

  const DspPeqState({
    required this.channel,
    required this.bandId,
    required this.frequencyHz,
    required this.gainDb,
    required this.q,
    required this.enabled,
  });

  bool get isValid =>
      channel >= 0 &&
      bandId >= 0 &&
      frequencyHz >= 20 &&
      frequencyHz <= 20000 &&
      gainDb.isFinite &&
      q.isFinite &&
      q > 0;
}

/// Address of a PEQ band whose current device state must be read.
class DspPeqStateRequest {
  final int channel;
  final int bandId;

  const DspPeqStateRequest({required this.channel, required this.bandId});
}

/// A verified point-in-time readback from one physical device.
class DspStateSnapshot {
  final String deviceIdentifier;
  final DateTime capturedAt;
  final List<DspPeqState> peqStates;

  DspStateSnapshot({
    required this.deviceIdentifier,
    required this.capturedAt,
    required List<DspPeqState> peqStates,
  }) : peqStates = List.unmodifiable(peqStates);

  DspPeqState? stateFor(DspPeqStateRequest request) {
    final matches = peqStates.where((state) =>
        state.channel == request.channel && state.bandId == request.bandId);
    return matches.length == 1 ? matches.single : null;
  }

  bool covers(Iterable<DspPeqStateRequest> requests) =>
      deviceIdentifier.isNotEmpty &&
      peqStates.every((state) => state.isValid) &&
      requests.every((request) => stateFor(request) != null);
}

/// Capability implemented by a hardware adapter only after its readback
/// protocol has been validated. Implementations may target Consumer ICP5,
/// PRO ADAU1701, or a future ADAU1466 transport.
abstract interface class DspStateReadCapability {
  Future<DspStateSnapshot> readPeqState({
    required String deviceIdentifier,
    required List<DspPeqStateRequest> requests,
  });
}

enum DspDeploymentPrerequisiteFailure {
  disconnected,
  identityNotValidated,
  deviceIdentityMismatch,
  emptyDeployment,
  readCapabilityUnavailable,
  snapshotMissing,
  snapshotDeviceMismatch,
  incompleteOrInvalidSnapshot,
}

class DspDeploymentPrerequisiteResult {
  final bool ready;
  final DspDeploymentPrerequisiteFailure? failure;

  const DspDeploymentPrerequisiteResult._(this.ready, this.failure);
  const DspDeploymentPrerequisiteResult.ready() : this._(true, null);
  const DspDeploymentPrerequisiteResult.blocked(
    DspDeploymentPrerequisiteFailure failure,
  ) : this._(false, failure);
}

/// Common, side-effect-free deployment prerequisite check.
///
/// It never invents state. A deployment is ready only when the target device
/// was identity-validated and a complete readback snapshot exists for every
/// PEQ band that may need rollback.
abstract final class DspDeploymentPrerequisiteCheck {
  static DspDeploymentPrerequisiteResult evaluate({
    required bool connected,
    required bool identityValidated,
    required String expectedDeviceIdentifier,
    required String? actualDeviceIdentifier,
    required List<DspPeqStateRequest> requiredStates,
    required bool readCapabilityAvailable,
    required DspStateSnapshot? snapshot,
  }) {
    if (!connected) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.disconnected,
      );
    }
    if (!identityValidated) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.identityNotValidated,
      );
    }
    if (expectedDeviceIdentifier.isEmpty ||
        actualDeviceIdentifier != expectedDeviceIdentifier) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.deviceIdentityMismatch,
      );
    }
    if (requiredStates.isEmpty) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.emptyDeployment,
      );
    }
    if (!readCapabilityAvailable) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.readCapabilityUnavailable,
      );
    }
    if (snapshot == null) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.snapshotMissing,
      );
    }
    if (snapshot.deviceIdentifier != expectedDeviceIdentifier) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.snapshotDeviceMismatch,
      );
    }
    if (!snapshot.covers(requiredStates)) {
      return const DspDeploymentPrerequisiteResult.blocked(
        DspDeploymentPrerequisiteFailure.incompleteOrInvalidSnapshot,
      );
    }
    return const DspDeploymentPrerequisiteResult.ready();
  }
}
