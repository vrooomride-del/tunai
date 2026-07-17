import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tunai/core/consumer_sound_profile.dart';
import 'package:tunai/core/tune_plan.dart';
import 'package:tunai/features/more/dev_simulation_screen.dart';
import 'package:tunai/core/consumer_dsp_physical_qa_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deployment metadata persists truthfully with the Sound Profile',
      () async {
    SharedPreferences.setMockInitialValues({});
    final notifier = ConsumerSoundProfileNotifier();
    final now = DateTime.utc(2026, 7, 17, 12);
    await notifier.add(ConsumerSoundProfile(
      id: 'profile-1',
      name: 'Test Tune',
      roomType: 'Desk',
      createdAt: now,
      updatedAt: now,
      micProfileName: 'Generic Phone Mic',
      confidence: 'High',
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: const [],
      tunePlanId: 'plan-1',
      generationStatus: ConsumerProfileGenerationStatus.generated,
      deploymentStatus: TuneDeploymentStatus.notDeployed,
    ));
    final record = ConsumerDspDeploymentRecord(
      tunePlanId: 'plan-1',
      deviceIdentifier: 'device-1',
      attemptedAt: now.add(const Duration(minutes: 1)),
      bandCount: 2,
      result: ConsumerDspDeploymentRecordResult.restored,
      dspApplied: false,
      failureCategory: 'invalidAck',
    );

    await notifier.recordDspDeployment('profile-1', record);

    expect(notifier.state.single.deploymentStatus,
        TuneDeploymentStatus.notDeployed);
    expect(notifier.state.single.dspDeploymentRecord?.result,
        ConsumerDspDeploymentRecordResult.restored);
    final prefs = await SharedPreferences.getInstance();
    final stored = jsonDecode(
      prefs.getString('tunai_consumer_sound_profiles')!,
    ) as List<dynamic>;
    final restored = ConsumerSoundProfile.fromJson(
      Map<String, dynamic>.from(stored.single as Map),
    );
    expect(restored.dspDeploymentRecord?.dspApplied, isFalse);
    expect(restored.dspDeploymentRecord?.failureCategory, 'invalidAck');
  });

  testWidgets('developer DSP action blocks without an original snapshot',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DevSimulationScreen()),
      ),
    );
    await tester.scrollUntilVisible(find.text('Apply DSP Test'), 120);
    await tester.tap(find.text('Apply DSP Test'));
    await tester.pump();

    expect(find.text('DSP TEST: BLOCKED: ORIGINAL SNAPSHOT REQUIRED'),
        findsOneWidget);
  });

  testWidgets('Run Full Flow persists and selects a matching QA pair',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DevSimulationScreen()),
      ),
    );
    await tester.tap(find.text('Run Full Flow (A→F)'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DevSimulationScreen)),
    );
    final selected = container.read(selectedConsumerProfileProvider);
    final storedPlan = await TunePlanStore.load();
    expect(storedPlan, isNotNull);
    expect(selected, isNotNull);
    expect(selected!.tunePlanId, storedPlan!.id);
    expect(selected.isSelected, isTrue);
    expect(selected.isActive, isTrue);
  });

  testWidgets('manual gain still requires explicit snapshot confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: DevSimulationScreen(
            physicalQaFixture: ConsumerDspPhysicalQaFixture(),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '-1.0');
    final applyButton = find.byKey(const ValueKey('apply_dsp_test'));
    await tester.scrollUntilVisible(
      applyButton,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -24));
    await tester.pump();
    await tester.tap(applyButton);
    await tester.pump();

    expect(find.text('DSP TEST: BLOCKED: SNAPSHOT CONFIRMATION REQUIRED'),
        findsOneWidget);
    expect(
        find.textContaining('Failure category: explicitConfirmationRequired'),
        findsOneWidget);
  });
}
