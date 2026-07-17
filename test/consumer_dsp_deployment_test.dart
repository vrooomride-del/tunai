import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/consumer_dsp_deployment.dart';
import 'package:tunai/core/tune_deployment_plan.dart';
import 'package:tunai/features/ble/icp5_peq_command_builder.dart';

class _FakeTransport implements ConsumerDspTransport {
  @override
  bool connected;
  @override
  bool handshakeValidated;
  @override
  String? deviceIdentifier;
  final List<List<int>> writes = [];
  final List<Object> responses;

  _FakeTransport({
    this.connected = true,
    this.handshakeValidated = true,
    this.deviceIdentifier = 'device-1',
    List<Object>? responses,
  }) : responses = responses ?? [];

  @override
  Future<List<int>> writeAndAwaitResponse(
    List<int> command, {
    required Duration timeout,
  }) async {
    writes.add(command);
    if (responses.isEmpty) return Icp5PeqCommandBuilder.peqAck;
    final response = responses.removeAt(0);
    if (response is List<int>) return response;
    if (response is Future<List<int>>) return response.timeout(timeout);
    throw response;
  }
}

TuneDeploymentPlan _plan({
  int channel = 1,
  int bandId = 0,
  int frequencyHz = 180,
  double gainDb = -2,
  double q = 2,
  bool enable = true,
  TuneDeploymentOriginalValues? original,
}) =>
    TuneDeploymentPlan(
      channel: channel,
      bandId: bandId,
      frequencyHz: frequencyHz,
      gainDb: gainDb,
      q: q,
      enable: enable,
      originalValues: original ??
          const TuneDeploymentOriginalValues(
            frequencyHz: 200,
            gainDb: 0,
            q: 1,
            enable: true,
          ),
    );

void main() {
  group('deployment guards', () {
    test(
        'blocks disconnected, unvalidated, wrong identity, and no confirmation',
        () async {
      Future<ConsumerDspDeploymentFailure?> run(
        _FakeTransport transport, {
        bool confirmed = true,
      }) async =>
          (await ConsumerDspDeploymentExecutor(transport: transport).execute(
            plans: [_plan()],
            expectedDeviceIdentifier: 'device-1',
            explicitlyConfirmed: confirmed,
          ))
              .failure;

      expect(await run(_FakeTransport(connected: false)),
          ConsumerDspDeploymentFailure.disconnected);
      expect(await run(_FakeTransport(handshakeValidated: false)),
          ConsumerDspDeploymentFailure.handshakeNotValidated);
      expect(await run(_FakeTransport(deviceIdentifier: 'other')),
          ConsumerDspDeploymentFailure.deviceIdentityMismatch);
      expect(await run(_FakeTransport(), confirmed: false),
          ConsumerDspDeploymentFailure.explicitConfirmationRequired);
    });

    test('blocks empty, excessive, unmapped, unsafe, and enable-changing plans',
        () async {
      Future<ConsumerDspDeploymentFailure?> run(
        List<TuneDeploymentPlan> plans,
      ) async =>
          (await ConsumerDspDeploymentExecutor(
            transport: _FakeTransport(),
          ).execute(
            plans: plans,
            expectedDeviceIdentifier: 'device-1',
            explicitlyConfirmed: true,
          ))
              .failure;

      expect(await run([]), ConsumerDspDeploymentFailure.emptyPlan);
      expect(await run([_plan(), _plan(bandId: 1), _plan(bandId: 2), _plan()]),
          ConsumerDspDeploymentFailure.tooManyBands);
      expect(await run([_plan(channel: 2)]),
          ConsumerDspDeploymentFailure.unsupportedChannelMapping);
      expect(await run([_plan(gainDb: 3.1)]),
          ConsumerDspDeploymentFailure.outOfBounds);
      expect(await run([_plan(enable: false)]),
          ConsumerDspDeploymentFailure.unsupportedParameter);
    });
  });

  test('writes sequentially and marks a band ACKED only after all commands',
      () async {
    final transport = _FakeTransport();
    final result =
        await ConsumerDspDeploymentExecutor(transport: transport).execute(
      plans: [_plan()],
      expectedDeviceIdentifier: 'device-1',
      explicitlyConfirmed: true,
    );

    expect(result.outcome, ConsumerDspDeploymentOutcome.applied);
    expect(result.acknowledgedCommandCount, 3);
    expect(result.plans.single.state, TuneDeploymentState.ACKED);
    expect(transport.writes, Icp5PeqCommandBuilder.commandsFor([_plan()]));
  });

  test('invalid ACK stops writes and restores ACKed commands in reverse order',
      () async {
    final plan = _plan();
    final transport = _FakeTransport(responses: [
      Icp5PeqCommandBuilder.peqAck,
      Icp5PeqCommandBuilder.peqAck,
      [0x55],
      Icp5PeqCommandBuilder.peqAck,
      Icp5PeqCommandBuilder.peqAck,
    ]);
    final result =
        await ConsumerDspDeploymentExecutor(transport: transport).execute(
      plans: [plan],
      expectedDeviceIdentifier: 'device-1',
      explicitlyConfirmed: true,
    );

    expect(result.outcome, ConsumerDspDeploymentOutcome.restored);
    expect(result.failure, ConsumerDspDeploymentFailure.invalidAck);
    expect(result.rollbackSucceeded, isTrue);
    expect(transport.writes.sublist(3), [
      Icp5PeqCommandBuilder.gain(
        channel: 1,
        bandId: 0,
        gainDb: plan.originalValues.gainDb,
      ),
      Icp5PeqCommandBuilder.frequency(
        channel: 1,
        bandId: 0,
        frequencyHz: plan.originalValues.frequencyHz,
      ),
    ]);
  });

  test('concurrent deployment is blocked while the first command waits',
      () async {
    final response = Completer<List<int>>();
    final firstTransport = _FakeTransport(responses: [response.future]);
    final executor = ConsumerDspDeploymentExecutor(
      transport: firstTransport,
      commandTimeout: const Duration(seconds: 1),
    );
    final first = executor.execute(
      plans: [_plan()],
      expectedDeviceIdentifier: 'device-1',
      explicitlyConfirmed: true,
    );
    await Future<void>.delayed(Duration.zero);

    final second = await ConsumerDspDeploymentExecutor(
      transport: _FakeTransport(),
    ).execute(
      plans: [_plan()],
      expectedDeviceIdentifier: 'device-1',
      explicitlyConfirmed: true,
    );
    expect(second.failure, ConsumerDspDeploymentFailure.concurrentDeployment);
    response.complete(Icp5PeqCommandBuilder.peqAck);
    expect((await first).outcome, ConsumerDspDeploymentOutcome.applied);
  });

  test('timeout is categorized and does not claim a rollback without an ACK',
      () async {
    final transport = _FakeTransport(
      responses: [Completer<List<int>>().future],
    );
    final result = await ConsumerDspDeploymentExecutor(
      transport: transport,
      commandTimeout: const Duration(milliseconds: 5),
    ).execute(
      plans: [_plan()],
      expectedDeviceIdentifier: 'device-1',
      explicitlyConfirmed: true,
    );

    expect(result.failure, ConsumerDspDeploymentFailure.timeout);
    expect(result.rollbackAttempted, isFalse);
    expect(result.dspApplied, isFalse);
  });

  test('rollback ACK failure is surfaced and never reports DSP applied',
      () async {
    final transport = _FakeTransport(responses: [
      Icp5PeqCommandBuilder.peqAck,
      [0x55],
      [0x55],
    ]);
    final result =
        await ConsumerDspDeploymentExecutor(transport: transport).execute(
      plans: [_plan()],
      expectedDeviceIdentifier: 'device-1',
      explicitlyConfirmed: true,
    );

    expect(result.failure, ConsumerDspDeploymentFailure.rollbackFailed);
    expect(result.rollbackAttempted, isTrue);
    expect(result.rollbackSucceeded, isFalse);
    expect(result.dspApplied, isFalse);
  });
}
