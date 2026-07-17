import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/room_measurement.dart';
import 'package:tunai/core/tune_deployment_plan.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/ble/icp5_peq_command_builder.dart';

void main() {
  test('frequency packet uses property 0x02 and uint16 little endian', () {
    expect(
      Icp5PeqCommandBuilder.frequency(
        channel: 1,
        bandId: 0,
        frequencyHz: 1800,
      ),
      [0x55, 0x0b, 0x1c, 0, 0, 0, 0x18, 1, 2, 0, 0x08, 0x07, 0xa6],
    );
  });

  test('gain packet uses property 0x01 and signed int8 tenths', () {
    expect(
      Icp5PeqCommandBuilder.gain(
        channel: 1,
        bandId: 0,
        gainDb: -1.0,
      ),
      [0x55, 0x0a, 0x1c, 0, 0, 0, 0x18, 1, 1, 0, 0xf6, 0x8b],
    );
  });

  test('q packet uses property 0x00 and uint8 tenths', () {
    expect(
      Icp5PeqCommandBuilder.q(channel: 1, bandId: 0, q: 2.0),
      [0x55, 0x0a, 0x1c, 0, 0, 0, 0x18, 1, 0, 0, 0x14, 0xa8],
    );
  });

  test('every generated command has a valid declared length and checksum', () {
    final commands = [
      Icp5PeqCommandBuilder.frequency(channel: 1, bandId: 0, frequencyHz: 1800),
      Icp5PeqCommandBuilder.gain(channel: 1, bandId: 0, gainDb: -1),
      Icp5PeqCommandBuilder.q(channel: 1, bandId: 0, q: 2),
    ];

    for (final command in commands) {
      expect(command.length, command[1] + 2);
      expect(
        command.last,
        Icp5PeqCommandBuilder.checksum(command.take(command.length - 1)),
      );
    }
  });

  test('ACK parsing accepts only the exact PEQ ACK', () {
    expect(
      Icp5PeqCommandBuilder.isValidPeqAck(
        [0x55, 0x07, 0xe1, 0, 0, 0, 0x18, 0, 0x55],
      ),
      isTrue,
    );
    expect(
      Icp5PeqCommandBuilder.isValidPeqAck(
        [0x55, 0x07, 0xe1, 0, 0, 0, 0x18, 1, 0x56],
      ),
      isFalse,
    );
  });

  test('restore generation uses the original value snapshot', () {
    const plan = TuneDeploymentPlan(
      channel: 1,
      bandId: 0,
      frequencyHz: 1801,
      gainDb: -0.9,
      q: 2.1,
      enable: true,
      originalValues: TuneDeploymentOriginalValues(
        frequencyHz: 1800,
        gainDb: -1.0,
        q: 2.0,
        enable: true,
      ),
    );

    expect(Icp5PeqCommandBuilder.restoreCommandsFor([plan]), [
      [0x55, 0x0b, 0x1c, 0, 0, 0, 0x18, 1, 2, 0, 0x08, 0x07, 0xa6],
      [0x55, 0x0a, 0x1c, 0, 0, 0, 0x18, 1, 1, 0, 0xf6, 0x8b],
      [0x55, 0x0a, 0x1c, 0, 0, 0, 0x18, 1, 0, 0, 0x14, 0xa8],
    ]);
  });

  test('TunePlan maps to deployment plans and a dry-run command list', () {
    final tunePlan = TunePlan(
      id: 'plan-1',
      sourceMeasurementId: 'measurement-1',
      createdAt: DateTime.utc(2026, 7, 17),
      bands: const [
        TuneCorrectionBand(
          frequencyHz: 1800,
          gainDb: -1,
          q: 2,
          evidenceReference: 'measurement-1:peak:1800',
          safetyValidated: true,
        ),
      ],
      rejectedCandidates: const [],
      safetyBounds: const TuneSafetyBounds(),
      measurementQuality: CaptureQualityStatus.valid,
      measurementConsistency: 1,
      warnings: const [],
    );
    final deploymentPlans = TuneDeploymentPlan.fromTunePlan(
      tunePlan,
      channel: 1,
      originalValues: const [
        TuneDeploymentOriginalValues(
          frequencyHz: 2000,
          gainDb: 0,
          q: 0.7,
          enable: true,
        ),
      ],
    );

    expect(deploymentPlans.single.bandId, 0);
    expect(deploymentPlans.single.state, TuneDeploymentState.CREATED);
    expect(Icp5PeqCommandBuilder.commandsFor(deploymentPlans), hasLength(3));
  });
}
