import 'consumer_dsp_deployment.dart';
import 'tune_deployment_plan.dart';
import '../features/ble/icp5_peq_command_builder.dart';

/// Developer-only, single-band physical ICP5 QA input.
///
/// Packet-generation tests prove captured examples for channel 1 / band 0 /
/// 1800 Hz / Q 2.0. They do not prove an original gain, so [originalGainDb]
/// must be entered from the current physical DSP state.
class ConsumerDspPhysicalQaFixture {
  static const captureEvidence =
      'test/tune_deployment_plan_test.dart: ICP5 Band 1 1800 Hz and Q 2.0 '
      'packet examples; original gain is developer-entered';

  final int channel;
  final int bandId;
  final int originalFrequencyHz;
  final double? originalGainDb;
  final double originalQ;
  final int testFrequencyHz;
  final double? testGainDb;
  final double testQ;
  final String evidenceSource;
  final bool snapshotConfirmed;

  const ConsumerDspPhysicalQaFixture({
    this.channel = ConsumerDspDeploymentExecutor.confirmedTunePlanChannel,
    this.bandId = 0,
    this.originalFrequencyHz = 1800,
    this.originalGainDb,
    this.originalQ = 2.0,
    this.testFrequencyHz = 1800,
    this.testGainDb,
    this.testQ = 2.0,
    this.evidenceSource = captureEvidence,
    this.snapshotConfirmed = false,
  });

  bool get snapshotComplete =>
      snapshotConfirmed &&
      originalGainDb != null &&
      testGainDb != null &&
      originalGainDb!.isFinite &&
      testGainDb!.isFinite &&
      originalGainDb! >= -6 &&
      originalGainDb! <= 3 &&
      testGainDb! >= -6 &&
      testGainDb! <= 3 &&
      ((originalGainDb! * 10) - (originalGainDb! * 10).round()).abs() < 1e-9;

  ConsumerDspPhysicalQaFixture withOriginalGain(double? gainDb) {
    final testGain = gainDb == null
        ? null
        : gainDb <= 2.9
            ? gainDb + 0.1
            : gainDb - 0.1;
    return ConsumerDspPhysicalQaFixture(
      channel: channel,
      bandId: bandId,
      originalFrequencyHz: originalFrequencyHz,
      originalGainDb: gainDb,
      originalQ: originalQ,
      testFrequencyHz: testFrequencyHz,
      testGainDb: testGain,
      testQ: testQ,
      evidenceSource: evidenceSource,
    );
  }

  ConsumerDspPhysicalQaFixture withSnapshotConfirmation(bool confirmed) =>
      ConsumerDspPhysicalQaFixture(
        channel: channel,
        bandId: bandId,
        originalFrequencyHz: originalFrequencyHz,
        originalGainDb: originalGainDb,
        originalQ: originalQ,
        testFrequencyHz: testFrequencyHz,
        testGainDb: testGainDb,
        testQ: testQ,
        evidenceSource: evidenceSource,
        snapshotConfirmed: confirmed,
      );

  List<TuneDeploymentPlan> createPlans() {
    if (!snapshotComplete ||
        channel != ConsumerDspDeploymentExecutor.confirmedTunePlanChannel ||
        bandId != 0 ||
        originalGainDb! < -6 ||
        originalGainDb! > 3 ||
        testGainDb! < -6 ||
        testGainDb! > 3) {
      return const [];
    }
    return [
      TuneDeploymentPlan(
        channel: channel,
        bandId: bandId,
        frequencyHz: testFrequencyHz,
        gainDb: testGainDb!,
        q: testQ,
        enable: true,
        originalValues: TuneDeploymentOriginalValues(
          frequencyHz: originalFrequencyHz,
          gainDb: originalGainDb!,
          q: originalQ,
          enable: true,
        ),
      ),
    ];
  }
}

class ConsumerDspPhysicalQaResultLog {
  final String guardResult;
  final int commandCount;
  final int acknowledgedCommandCount;
  final ConsumerDspDeploymentOutcome outcome;
  final bool rollbackAttempted;
  final bool rollbackSucceeded;
  final String failureCategory;
  final String finalConfidence;
  final List<ConsumerDspCommandDiagnostic> commandDiagnostics;

  const ConsumerDspPhysicalQaResultLog({
    required this.guardResult,
    required this.commandCount,
    required this.acknowledgedCommandCount,
    required this.outcome,
    required this.rollbackAttempted,
    required this.rollbackSucceeded,
    required this.failureCategory,
    required this.finalConfidence,
    this.commandDiagnostics = const [],
  });

  factory ConsumerDspPhysicalQaResultLog.fromDeployment(
    ConsumerDspDeploymentResult result, {
    required int commandCount,
  }) =>
      ConsumerDspPhysicalQaResultLog(
        guardResult: result.outcome == ConsumerDspDeploymentOutcome.blocked
            ? 'BLOCKED'
            : 'PASS',
        commandCount: commandCount,
        acknowledgedCommandCount: result.acknowledgedCommandCount,
        outcome: result.outcome,
        rollbackAttempted: result.rollbackAttempted,
        rollbackSucceeded: result.rollbackSucceeded,
        failureCategory: result.failure?.name ?? 'none',
        finalConfidence: switch (result.outcome) {
          ConsumerDspDeploymentOutcome.applied => 'applied',
          ConsumerDspDeploymentOutcome.restored => 'notDeployed',
          ConsumerDspDeploymentOutcome.blocked => 'notDeployed',
          ConsumerDspDeploymentOutcome.failed => 'unknown',
        },
        commandDiagnostics: result.commandDiagnostics,
      );

  String get displayText => 'Guard: $guardResult\n'
      'Command count: $commandCount\n'
      'ACKed command count: $acknowledgedCommandCount\n'
      'Outcome: ${outcome.name}\n'
      'Rollback attempted: $rollbackAttempted\n'
      'Rollback succeeded: $rollbackSucceeded\n'
      'Failure category: $failureCategory\n'
      'Final confidence: $finalConfidence\n'
      'Audible verification: not performed\n'
      'Physical speaker mapping: not verified'
      '${commandDiagnostics.isEmpty ? "" : "\n\n${commandDiagnostics.map(_formatCommand).join("\n\n")}"}';

  static String _formatCommand(ConsumerDspCommandDiagnostic diagnostic) {
    final rx = diagnostic.rawRxNotifications.isEmpty
        ? 'RX: none\nRX length: 0'
        : [
            for (var index = 0;
                index < diagnostic.rawRxNotifications.length;
                index++) ...[
              'RX[${index + 1}]: ${ConsumerDspCommandDiagnostic.hex(diagnostic.rawRxNotifications[index])}',
              'RX[${index + 1}] length: ${diagnostic.rawRxNotifications[index].length}',
              'RX[${index + 1}] elapsed: ${index < diagnostic.rawRxElapsedMilliseconds.length ? diagnostic.rawRxElapsedMilliseconds[index] : diagnostic.elapsedMilliseconds} ms',
            ],
          ].join('\n');
    final property = switch (diagnostic.property) {
      ConsumerDspCommandProperty.frequency => 'Frequency',
      ConsumerDspCommandProperty.gain => 'Gain',
      ConsumerDspCommandProperty.q => 'Q',
    };
    return 'Command ${diagnostic.commandIndex} — $property\n'
        'TX: ${ConsumerDspCommandDiagnostic.hex(diagnostic.txPacket)}\n'
        'GATT write completion: ${diagnostic.gattWriteCompleted}\n'
        '$rx\n'
        'Expected ACK: ${ConsumerDspCommandDiagnostic.hex(Icp5PeqCommandBuilder.peqAck)}\n'
        'Validation: ${diagnostic.ackParserResult ? "validAck" : "invalidAck"}\n'
        'Transport error: ${diagnostic.transportError ?? "none"}\n'
        'Elapsed: ${diagnostic.elapsedMilliseconds} ms';
  }
}
