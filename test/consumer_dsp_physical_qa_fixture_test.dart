import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/consumer_dsp_deployment.dart';
import 'package:tunai/core/consumer_dsp_physical_qa_fixture.dart';
import 'package:tunai/core/tune_deployment_plan.dart';

void main() {
  group('physical ICP5 QA fixture', () {
    test('FactoryScreen routes the fixture only below its debug guard', () {
      final source =
          File('lib/features/more/factory_screen.dart').readAsStringSync();
      final guard = source.indexOf('if (kDebugMode)');
      final route = source.indexOf(
        'physicalQaFixture: ConsumerDspPhysicalQaFixture()',
      );
      expect(guard, greaterThanOrEqualTo(0));
      expect(route, greaterThan(guard));
      expect(route - guard, lessThan(1200));
    });

    test('confirmed fixture creates exactly one capture-backed Band 1 plan',
        () {
      final fixture = const ConsumerDspPhysicalQaFixture()
          .withOriginalGain(-1.0)
          .withSnapshotConfirmation(true);
      final plans = fixture.createPlans();

      expect(plans, hasLength(1));
      final plan = plans.single;
      expect(
          plan.channel, ConsumerDspDeploymentExecutor.confirmedTunePlanChannel);
      expect(plan.bandId, 0);
      expect(plan.frequencyHz, 1800);
      expect(plan.originalValues.frequencyHz, 1800);
      expect(plan.q, 2.0);
      expect(plan.originalValues.q, 2.0);
      expect((plan.gainDb - plan.originalValues.gainDb).abs(),
          closeTo(0.1, 1e-10));
      expect(plan.enable, isTrue);
      expect(plan.originalValues.enable, isTrue);
    });

    test('incomplete gain or missing confirmation produces no plan', () {
      expect(const ConsumerDspPhysicalQaFixture().createPlans(), isEmpty);
      expect(
        const ConsumerDspPhysicalQaFixture()
            .withOriginalGain(-1.0)
            .createPlans(),
        isEmpty,
      );
    });

    test('wrong channel remains blocked and more than one band is never made',
        () {
      final wrongChannel = const ConsumerDspPhysicalQaFixture(channel: 2)
          .withOriginalGain(-1.0)
          .withSnapshotConfirmation(true);
      expect(wrongChannel.createPlans(), isEmpty);

      final valid = const ConsumerDspPhysicalQaFixture()
          .withOriginalGain(-1.0)
          .withSnapshotConfirmation(true);
      expect(valid.createPlans().length, lessThanOrEqualTo(1));
    });
  });

  group('physical QA result truth', () {
    const plan = TuneDeploymentPlan(
      channel: 1,
      bandId: 0,
      frequencyHz: 1800,
      gainDb: -0.9,
      q: 2,
      enable: true,
      originalValues: TuneDeploymentOriginalValues(
        frequencyHz: 1800,
        gainDb: -1,
        q: 2,
        enable: true,
      ),
    );

    test('applied, restored, and failed confidence is reported truthfully', () {
      const applied = ConsumerDspDeploymentResult(
        outcome: ConsumerDspDeploymentOutcome.applied,
        plans: [plan],
        acknowledgedCommandCount: 3,
      );
      const restored = ConsumerDspDeploymentResult(
        outcome: ConsumerDspDeploymentOutcome.restored,
        plans: [plan],
        failure: ConsumerDspDeploymentFailure.invalidAck,
        acknowledgedCommandCount: 2,
        rollbackAttempted: true,
        rollbackSucceeded: true,
      );
      const failed = ConsumerDspDeploymentResult(
        outcome: ConsumerDspDeploymentOutcome.failed,
        plans: [plan],
        failure: ConsumerDspDeploymentFailure.rollbackFailed,
        acknowledgedCommandCount: 1,
        rollbackAttempted: true,
      );

      expect(
        ConsumerDspPhysicalQaResultLog.fromDeployment(applied, commandCount: 3)
            .finalConfidence,
        'applied',
      );
      expect(
        ConsumerDspPhysicalQaResultLog.fromDeployment(restored, commandCount: 3)
            .finalConfidence,
        'notDeployed',
      );
      final failedLog = ConsumerDspPhysicalQaResultLog.fromDeployment(
        failed,
        commandCount: 3,
      );
      expect(failedLog.finalConfidence, 'unknown');
      expect(
          failedLog.displayText, contains('Failure category: rollbackFailed'));
      expect(failedLog.displayText,
          contains('Audible verification: not performed'));
    });
  });
}
