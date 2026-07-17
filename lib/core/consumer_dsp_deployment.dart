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
  final List<ConsumerDspCommandDiagnostic> commandDiagnostics;

  const ConsumerDspDeploymentResult({
    required this.outcome,
    required this.plans,
    this.failure,
    this.acknowledgedCommandCount = 0,
    this.rollbackAttempted = false,
    this.rollbackSucceeded = false,
    this.commandDiagnostics = const [],
  });

  bool get dspApplied => outcome == ConsumerDspDeploymentOutcome.applied;
}

enum ConsumerDspCommandProperty { frequency, gain, q }

class ConsumerDspCommandDiagnostic {
  final int commandIndex;
  final ConsumerDspCommandProperty property;
  final List<int> txPacket;
  final bool gattWriteCompleted;
  final List<List<int>> rawRxNotifications;
  final List<int> rawRxElapsedMilliseconds;
  final List<int> responseBytes;
  final bool ackParserResult;
  final String? transportError;
  final int elapsedMilliseconds;

  const ConsumerDspCommandDiagnostic({
    required this.commandIndex,
    required this.property,
    required this.txPacket,
    required this.gattWriteCompleted,
    required this.rawRxNotifications,
    this.rawRxElapsedMilliseconds = const [],
    required this.responseBytes,
    required this.ackParserResult,
    required this.elapsedMilliseconds,
    this.transportError,
  });

  static String hex(Iterable<int> bytes) => bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(' ');
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

  Future<ConsumerBleApplicationExchange> writeAndAwaitExchange(
    List<int> command, {
    required Duration timeout,
  }) =>
      service.sendApplicationFrameAndAwaitExchange(
        command,
        timeout: timeout,
        // Select only a PEQ response-shaped frame. The executor still applies
        // the unchanged byte-for-byte ACK validator and rejects any malformed
        // candidate as invalidAck.
        frameMatcher: (frame) =>
            frame.length >= 7 && frame[2] == 0xe1 && frame[6] == 0x18,
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
    final diagnostics = <ConsumerDspCommandDiagnostic>[];
    try {
      final commands = _commands(current);
      for (final command in commands) {
        current[command.planIndex] = current[command.planIndex]
            .copyWith(state: TuneDeploymentState.SENT);
        List<int> ack;
        if (transport is ConsumerBleDspTransport) {
          try {
            final exchange = await (transport as ConsumerBleDspTransport)
                .writeAndAwaitExchange(
              command.apply,
              timeout: commandTimeout,
            );
            ack = exchange.matchedFrame;
            diagnostics.add(_diagnostic(
              command,
              diagnostics.length + 1,
              exchange,
            ));
          } on ConsumerBleApplicationException catch (error) {
            diagnostics.add(_diagnostic(
              command,
              diagnostics.length + 1,
              error.exchange,
              transportError: error.cause.toString(),
            ));
            throw error.cause;
          }
        } else {
          ack = await transport.writeAndAwaitResponse(
            command.apply,
            timeout: commandTimeout,
          );
          diagnostics.add(ConsumerDspCommandDiagnostic(
            commandIndex: diagnostics.length + 1,
            property: command.property,
            txPacket: List.unmodifiable(command.apply),
            gattWriteCompleted: true,
            rawRxNotifications: [List.unmodifiable(ack)],
            rawRxElapsedMilliseconds: const [0],
            responseBytes: List.unmodifiable(ack),
            ackParserResult: Icp5PeqCommandBuilder.isValidPeqAck(ack),
            elapsedMilliseconds: 0,
          ));
        }
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
        commandDiagnostics: List.unmodifiable(diagnostics),
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
        commandDiagnostics: List.unmodifiable(diagnostics),
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
            ConsumerDspCommandProperty.frequency,
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
            ConsumerDspCommandProperty.gain,
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
            ConsumerDspCommandProperty.q,
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

  ConsumerDspCommandDiagnostic _diagnostic(
    _DeploymentCommand command,
    int commandIndex,
    ConsumerBleApplicationExchange exchange, {
    String? transportError,
  }) =>
      ConsumerDspCommandDiagnostic(
        commandIndex: commandIndex,
        property: command.property,
        txPacket: List.unmodifiable(command.apply),
        gattWriteCompleted: exchange.gattWriteCompleted,
        rawRxNotifications: exchange.rawNotifications,
        rawRxElapsedMilliseconds: exchange.rawNotificationElapsedMilliseconds,
        responseBytes: exchange.matchedFrame,
        ackParserResult:
            Icp5PeqCommandBuilder.isValidPeqAck(exchange.matchedFrame),
        transportError: transportError,
        elapsedMilliseconds: exchange.elapsedMilliseconds,
      );

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
  final ConsumerDspCommandProperty property;
  final List<int> apply;
  final List<int> restore;
  const _DeploymentCommand(
    this.planIndex,
    this.property,
    this.apply,
    this.restore,
  );
}

class _DeploymentException implements Exception {
  final ConsumerDspDeploymentFailure failure;
  const _DeploymentException(this.failure);
}
