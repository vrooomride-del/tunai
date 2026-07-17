import 'dart:async';

import '../features/ble/consumer_ble_service.dart';
import '../features/ble/icp5_peq_command_builder.dart';
import 'tune_deployment_plan.dart';

enum ConsumerDspDeploymentFailure {
  disconnected,
  handshakeNotValidated,
  deviceIdentityMismatch,
  emptyPlan,
  tooManyBands,
  unsupportedChannelMapping,
  unsupportedParameter,
  outOfBounds,
  missingOriginalSnapshot,
  explicitConfirmationRequired,
  concurrentDeployment,
  timeout,
  invalidAck,
  disconnectDuringWrite,
  writeError,
  rollbackFailed,
}

enum ConsumerDspDeploymentOutcome { applied, restored, failed, blocked }

class ConsumerDspDeploymentResult {
  final ConsumerDspDeploymentOutcome outcome;
  final ConsumerDspDeploymentFailure? failure;
  final List<TuneDeploymentPlan> plans;
  final int acknowledgedCommandCount;
  final bool rollbackAttempted;
  final bool rollbackSucceeded;

  const ConsumerDspDeploymentResult({
    required this.outcome,
    required this.plans,
    this.failure,
    this.acknowledgedCommandCount = 0,
    this.rollbackAttempted = false,
    this.rollbackSucceeded = false,
  });

  bool get dspApplied => outcome == ConsumerDspDeploymentOutcome.applied;
}

abstract interface class ConsumerDspTransport {
  bool get connected;
  bool get handshakeValidated;
  String? get deviceIdentifier;
  Future<List<int>> writeAndAwaitResponse(
    List<int> command, {
    required Duration timeout,
  });
}

class ConsumerBleDspTransport implements ConsumerDspTransport {
  final ConsumerBleService service;

  const ConsumerBleDspTransport(this.service);

  @override
  bool get connected => service.state.connected;
  @override
  bool get handshakeValidated => service.supportedIdentityValidated;
  @override
  String? get deviceIdentifier => service.validatedDeviceIdentifier;

  @override
  Future<List<int>> writeAndAwaitResponse(
    List<int> command, {
    required Duration timeout,
  }) =>
      service.sendApplicationFrameAndAwaitResponse(
        command,
        timeout: timeout,
      );
}

class ConsumerDspDeploymentExecutor {
  static const confirmedTunePlanChannel = 1;

  final ConsumerDspTransport transport;
  final Duration commandTimeout;
  bool _inProgress = false;

  ConsumerDspDeploymentExecutor({
    required this.transport,
    this.commandTimeout = const Duration(seconds: 3),
  });

  Future<ConsumerDspDeploymentResult> execute({
    required List<TuneDeploymentPlan> plans,
    required String expectedDeviceIdentifier,
    required bool explicitlyConfirmed,
  }) async {
    final guard = _guard(
      plans: plans,
      expectedDeviceIdentifier: expectedDeviceIdentifier,
      explicitlyConfirmed: explicitlyConfirmed,
    );
    if (guard != null) return guard;
    _inProgress = true;
    var current = plans
        .map((plan) => plan.copyWith(state: TuneDeploymentState.CREATED))
        .toList();
    final acknowledged = <_DeploymentCommand>[];
    try {
      final commands = _commands(current);
      for (final command in commands) {
        current[command.planIndex] = current[command.planIndex]
            .copyWith(state: TuneDeploymentState.SENT);
        final ack = await transport.writeAndAwaitResponse(
          command.apply,
          timeout: commandTimeout,
        );
        if (!Icp5PeqCommandBuilder.isValidPeqAck(ack)) {
          throw const _DeploymentException(
            ConsumerDspDeploymentFailure.invalidAck,
          );
        }
        acknowledged.add(command);
        if (commands
            .where((entry) => entry.planIndex == command.planIndex)
            .every(acknowledged.contains)) {
          current[command.planIndex] = current[command.planIndex]
              .copyWith(state: TuneDeploymentState.ACKED);
        }
      }
      return ConsumerDspDeploymentResult(
        outcome: ConsumerDspDeploymentOutcome.applied,
        plans: List.unmodifiable(current),
        acknowledgedCommandCount: acknowledged.length,
      );
    } catch (error) {
      final failure = _classify(error);
      final rollbackSucceeded = await _rollback(acknowledged);
      current = [
        for (var index = 0; index < current.length; index++)
          if (acknowledged.any((command) => command.planIndex == index))
            current[index].copyWith(
              state: rollbackSucceeded
                  ? TuneDeploymentState.RESTORED
                  : TuneDeploymentState.FAILED,
            )
          else
            current[index].copyWith(state: TuneDeploymentState.FAILED),
      ];
      return ConsumerDspDeploymentResult(
        outcome: rollbackSucceeded && acknowledged.isNotEmpty
            ? ConsumerDspDeploymentOutcome.restored
            : ConsumerDspDeploymentOutcome.failed,
        failure: rollbackSucceeded
            ? failure
            : ConsumerDspDeploymentFailure.rollbackFailed,
        plans: List.unmodifiable(current),
        acknowledgedCommandCount: acknowledged.length,
        rollbackAttempted: acknowledged.isNotEmpty,
        rollbackSucceeded: rollbackSucceeded && acknowledged.isNotEmpty,
      );
    } finally {
      _inProgress = false;
    }
  }

  ConsumerDspDeploymentResult? _guard({
    required List<TuneDeploymentPlan> plans,
    required String expectedDeviceIdentifier,
    required bool explicitlyConfirmed,
  }) {
    ConsumerDspDeploymentFailure? failure;
    if (_inProgress) {
      failure = ConsumerDspDeploymentFailure.concurrentDeployment;
    } else if (!transport.connected) {
      failure = ConsumerDspDeploymentFailure.disconnected;
    } else if (!transport.handshakeValidated) {
      failure = ConsumerDspDeploymentFailure.handshakeNotValidated;
    } else if (expectedDeviceIdentifier.isEmpty ||
        transport.deviceIdentifier != expectedDeviceIdentifier) {
      failure = ConsumerDspDeploymentFailure.deviceIdentityMismatch;
    } else if (!explicitlyConfirmed) {
      failure = ConsumerDspDeploymentFailure.explicitConfirmationRequired;
    } else if (plans.isEmpty) {
      failure = ConsumerDspDeploymentFailure.emptyPlan;
    } else if (plans.length > 3) {
      failure = ConsumerDspDeploymentFailure.tooManyBands;
    } else if (plans.any((plan) => plan.channel != confirmedTunePlanChannel)) {
      failure = ConsumerDspDeploymentFailure.unsupportedChannelMapping;
    } else if (plans.any((plan) => plan.bandId < 0 || plan.bandId > 2)) {
      failure = ConsumerDspDeploymentFailure.unsupportedParameter;
    } else if (plans.any((plan) =>
        plan.frequencyHz < 20 ||
        plan.frequencyHz > 20000 ||
        plan.gainDb < -6 ||
        plan.gainDb > 3 ||
        plan.q < 0.3 ||
        plan.q > 10)) {
      failure = ConsumerDspDeploymentFailure.outOfBounds;
    } else if (plans.any((plan) =>
        plan.originalValues.frequencyHz < 20 ||
        plan.originalValues.frequencyHz > 20000 ||
        plan.originalValues.gainDb < -6 ||
        plan.originalValues.gainDb > 3 ||
        plan.originalValues.q < 0.3 ||
        plan.originalValues.q > 10)) {
      failure = ConsumerDspDeploymentFailure.missingOriginalSnapshot;
    } else if (plans.any(
        (plan) => !plan.enable || plan.enable != plan.originalValues.enable)) {
      failure = ConsumerDspDeploymentFailure.unsupportedParameter;
    }
    if (failure == null) return null;
    return ConsumerDspDeploymentResult(
      outcome: ConsumerDspDeploymentOutcome.blocked,
      failure: failure,
      plans: List.unmodifiable(plans),
    );
  }

  List<_DeploymentCommand> _commands(List<TuneDeploymentPlan> plans) => [
        for (var index = 0; index < plans.length; index++) ...[
          _DeploymentCommand(
            index,
            Icp5PeqCommandBuilder.frequency(
              channel: plans[index].channel,
              bandId: plans[index].bandId,
              frequencyHz: plans[index].frequencyHz,
            ),
            Icp5PeqCommandBuilder.frequency(
              channel: plans[index].channel,
              bandId: plans[index].bandId,
              frequencyHz: plans[index].originalValues.frequencyHz,
            ),
          ),
          _DeploymentCommand(
            index,
            Icp5PeqCommandBuilder.gain(
              channel: plans[index].channel,
              bandId: plans[index].bandId,
              gainDb: plans[index].gainDb,
            ),
            Icp5PeqCommandBuilder.gain(
              channel: plans[index].channel,
              bandId: plans[index].bandId,
              gainDb: plans[index].originalValues.gainDb,
            ),
          ),
          _DeploymentCommand(
            index,
            Icp5PeqCommandBuilder.q(
              channel: plans[index].channel,
              bandId: plans[index].bandId,
              q: plans[index].q,
            ),
            Icp5PeqCommandBuilder.q(
              channel: plans[index].channel,
              bandId: plans[index].bandId,
              q: plans[index].originalValues.q,
            ),
          ),
        ],
      ];

  Future<bool> _rollback(List<_DeploymentCommand> acknowledged) async {
    if (acknowledged.isEmpty) return true;
    for (final command in acknowledged.reversed) {
      try {
        final ack = await transport.writeAndAwaitResponse(
          command.restore,
          timeout: commandTimeout,
        );
        if (!Icp5PeqCommandBuilder.isValidPeqAck(ack)) return false;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  ConsumerDspDeploymentFailure _classify(Object error) {
    if (error is _DeploymentException) return error.failure;
    if (error is TimeoutException) return ConsumerDspDeploymentFailure.timeout;
    if (!transport.connected) {
      return ConsumerDspDeploymentFailure.disconnectDuringWrite;
    }
    return ConsumerDspDeploymentFailure.writeError;
  }
}

class _DeploymentCommand {
  final int planIndex;
  final List<int> apply;
  final List<int> restore;
  const _DeploymentCommand(this.planIndex, this.apply, this.restore);
}

class _DeploymentException implements Exception {
  final ConsumerDspDeploymentFailure failure;
  const _DeploymentException(this.failure);
}
