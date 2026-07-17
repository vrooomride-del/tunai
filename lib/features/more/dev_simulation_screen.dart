// ── Developer / QA Simulation Screen ─────────────────────────────────────────
// Access: FACTORY MODE (PIN 1234) → "Developer Simulation" button.
// Only shown in debug builds (kDebugMode guard in factory_screen.dart).
// NOT accessible from the normal consumer flow.
//
// TODO(release): Remove or gate DevSimulationScreen from production release.
//   The kDebugMode guard in factory_screen.dart is active; confirm before shipping.
//
// Simulates the full consumer state machine without real hardware:
//   connected → roomSelected → roomScanCompleted
//   → acousticTuneCreated → soundProfileActive → listenReady
// No real DSP writes, no real BLE, no real microphone input.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/room_scan_result.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/install_location.dart';
import '../../core/consumer_dsp_deployment.dart';
import '../../core/consumer_dsp_physical_qa_fixture.dart';
import '../../core/consumer_dsp_physical_qa_setup.dart';
import '../../core/tune_deployment_plan.dart';
import '../../core/tune_plan.dart';
import '../ble/ble_controller.dart';

class DevSimulationScreen extends ConsumerStatefulWidget {
  /// A deployment plan with externally captured original values must be
  /// supplied by a developer harness. The normal app never creates one.
  final List<TuneDeploymentPlan> dspTestPlans;
  final ConsumerDspPhysicalQaFixture? physicalQaFixture;

  const DevSimulationScreen({
    super.key,
    this.dspTestPlans = const [],
    this.physicalQaFixture,
  });

  @override
  ConsumerState<DevSimulationScreen> createState() =>
      _DevSimulationScreenState();
}

class _DevSimulationScreenState extends ConsumerState<DevSimulationScreen> {
  String _log = '';
  String _dspStatus = 'IDLE';
  String _dspResultDetails = 'No physical QA result in this session.';
  late ConsumerDspPhysicalQaFixture? _physicalQaFixture;
  final _originalGainController = TextEditingController();
  ConsumerDspQaPairStatus _qaPairStatus = const ConsumerDspQaPairStatus(
    storedTunePlanId: null,
    selectedProfileId: null,
    selectedProfileTunePlanId: null,
    matches: false,
    blockReason: 'notChecked',
  );

  @override
  void initState() {
    super.initState();
    _physicalQaFixture = widget.physicalQaFixture;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshQaPairStatus());
  }

  @override
  void dispose() {
    _originalGainController.dispose();
    super.dispose();
  }

  List<TuneDeploymentPlan> get _validatedDspTestPlans =>
      _physicalQaFixture?.createPlans() ?? widget.dspTestPlans;

  void _appendLog(String msg) => setState(() => _log += '✓ $msg\n');
  void _appendErr(String msg) => setState(() => _log += '✗ $msg\n');

  void _blockDsp(String reason, String failureCategory) {
    setState(() {
      _dspStatus = 'BLOCKED: $reason';
      _dspResultDetails = 'Guard: BLOCKED\n'
          'Command count: 0\n'
          'ACKed command count: 0\n'
          'Outcome: blocked\n'
          'Rollback attempted: false\n'
          'Rollback succeeded: false\n'
          'Failure category: $failureCategory\n'
          'Final confidence: notDeployed';
    });
  }

  Future<ConsumerDspQaPairStatus> _refreshQaPairStatus() async {
    final status = ConsumerDspQaPairStatus.evaluate(
      storedTunePlan: await TunePlanStore.load(),
      selectedProfile: ref.read(selectedConsumerProfileProvider),
    );
    if (mounted) setState(() => _qaPairStatus = status);
    return status;
  }

  Future<void> _applyDspTest() async {
    final plans = _validatedDspTestPlans;
    if (plans.isEmpty) {
      final originalGainPresent = _physicalQaFixture?.originalGainDb != null;
      final snapshotConfirmed = _physicalQaFixture?.snapshotConfirmed ?? false;
      _blockDsp(
        !originalGainPresent
            ? 'ORIGINAL SNAPSHOT REQUIRED'
            : snapshotConfirmed
                ? 'ORIGINAL SNAPSHOT INVALID'
                : 'SNAPSHOT CONFIRMATION REQUIRED',
        !originalGainPresent
            ? 'missingOriginalSnapshot'
            : snapshotConfirmed
                ? 'invalidOriginalSnapshot'
                : 'explicitConfirmationRequired',
      );
      _appendErr('DSP test blocked — no captured original-value snapshot');
      return;
    }
    final pairStatus = await _refreshQaPairStatus();
    final profile = ref.read(selectedConsumerProfileProvider);
    final tunePlan = await TunePlanStore.load();
    if (!pairStatus.matches || profile == null || tunePlan == null) {
      _blockDsp('TUNE PLAN MISMATCH', 'tunePlanMismatch');
      _appendErr('DSP test blocked — ${pairStatus.blockReason}: '
          'stored=${pairStatus.storedTunePlanId}, '
          'profile=${pairStatus.selectedProfileId}, '
          'profilePlan=${pairStatus.selectedProfileTunePlanId}');
      return;
    }
    final service = ref.read(consumerBleServiceProvider);
    if (!service.state.connected) {
      _blockDsp('BLE TRANSPORT UNAVAILABLE', 'disconnected');
      _appendErr('DSP test blocked — BLE transport is unavailable');
      return;
    }
    final deviceIdentifier = service.validatedDeviceIdentifier;
    if (deviceIdentifier == null) {
      _blockDsp('DEVICE NOT VALIDATED', 'handshakeNotValidated');
      _appendErr(
          'DSP test blocked — connected device is not identity-validated');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Apply DSP Test?'),
            content: Text(
              'Write ${plans.length} PEQ band(s) to the '
              'validated test device. This is a developer-only action.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Apply DSP Test'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) {
      setState(() => _dspStatus = 'CANCELLED');
      return;
    }
    setState(() => _dspStatus = 'WRITING');
    final attemptedAt = DateTime.now();
    final result = await ConsumerDspDeploymentExecutor(
      transport: ConsumerBleDspTransport(service),
    ).execute(
      plans: plans,
      expectedDeviceIdentifier: deviceIdentifier,
      explicitlyConfirmed: true,
    );
    final recordResult = switch (result.outcome) {
      ConsumerDspDeploymentOutcome.applied =>
        ConsumerDspDeploymentRecordResult.applied,
      ConsumerDspDeploymentOutcome.restored =>
        ConsumerDspDeploymentRecordResult.restored,
      ConsumerDspDeploymentOutcome.failed =>
        ConsumerDspDeploymentRecordResult.failed,
      ConsumerDspDeploymentOutcome.blocked =>
        ConsumerDspDeploymentRecordResult.blocked,
    };
    await ref.read(consumerSoundProfileProvider.notifier).recordDspDeployment(
          profile.id,
          ConsumerDspDeploymentRecord(
            tunePlanId: tunePlan.id,
            deviceIdentifier: deviceIdentifier,
            attemptedAt: attemptedAt,
            bandCount: plans.length,
            result: recordResult,
            dspApplied: result.dspApplied,
            failureCategory: result.failure?.name,
          ),
        );
    final resultLog = ConsumerDspPhysicalQaResultLog.fromDeployment(
      result,
      commandCount: plans.length * 3,
    );
    setState(() {
      _dspStatus = result.outcome.name.toUpperCase();
      _dspResultDetails = resultLog.displayText;
    });
    _appendLog('DSP test result: ${result.outcome.name}');
  }

  Future<void> _simulateInstallLocation() async {
    try {
      _appendLog('Set Install Location → Living Room');
      ref.read(installLocationProvider.notifier).state =
          InstallLocation.livingRoom;
      _appendLog('installLocationProvider: Living Room (거실)');
    } catch (e) {
      _appendErr('Set Install Location failed: $e');
      rethrow;
    }
  }

  Future<void> _simulateRoomScan() async {
    try {
      _appendLog('Simulate Room Scan started...');
      await Future.delayed(const Duration(milliseconds: 400));
      final result = RoomScanResult(
        roomType: 'Living Room',
        micProfileName: 'Generic Phone Mic',
        completedAt: DateTime.now(),
        confidence: 'Medium',
        cards: kDefaultResultCards.toList(),
      );
      await ref.read(roomScanResultProvider.notifier).saveResult(result);
      final verify = ref.read(roomScanResultProvider);
      if (verify == null) {
        _appendErr(
            'roomScanResultProvider → null after save (persistence error)');
      } else {
        _appendLog(
            'roomScanResultProvider → saved (${verify.roomType}, ${verify.cards.length} cards)');
      }
    } catch (e) {
      _appendErr('Simulate Room Scan failed: $e');
      rethrow;
    }
  }

  Future<void> _simulateCreateTune() async {
    try {
      final scan = ref.read(roomScanResultProvider);
      if (scan == null) {
        _appendErr('No room scan — run Simulate Room Scan first');
        return;
      }
      _appendLog('Prepare developer QA TunePlan/profile pair started...');
      await Future.delayed(const Duration(milliseconds: 400));
      final status = await ConsumerDspPhysicalQaSetup.prepare(
        scan: scan,
        profiles: ref.read(consumerSoundProfileProvider.notifier),
        now: DateTime.now(),
      );
      setState(() => _qaPairStatus = status);
      _appendLog('Stored TunePlan=${status.storedTunePlanId}; '
          'selectedProfile=${status.selectedProfileId}; '
          'selectedProfileTunePlan=${status.selectedProfileTunePlanId}; '
          'match=${status.matches}');
    } catch (e) {
      _appendErr('Simulate Create Tune failed: $e');
      rethrow;
    }
  }

  Future<void> _simulateApplyProfile() async {
    try {
      final profiles = ref.read(consumerSoundProfileProvider);
      final selected = ref.read(selectedConsumerProfileProvider);
      final ready = selected?.status == ConsumerProfileStatus.ready
          ? [selected!]
          : profiles
              .where((p) => p.status == ConsumerProfileStatus.ready)
              .toList();
      if (ready.isEmpty) {
        _appendErr('No ready profile — run Simulate Acoustic Tune first');
        return;
      }
      _appendLog('Simulate Apply Sound Profile: "${ready.first.name}"');
      await ref
          .read(consumerSoundProfileProvider.notifier)
          .setActive(ready.first.id);
      await _refreshQaPairStatus();
      final active = ref.read(activeConsumerProfileProvider);
      if (active == null) {
        _appendErr(
            'activeConsumerProfileProvider → null after setActive (unexpected)');
      } else {
        _appendLog(
            'activeConsumerProfileProvider → "${active.name}" (status: ${active.status.name})');
        _appendLog(
            'TUNE tab should now show State F. LISTEN tab shows ConsumerActiveView.');
      }
    } catch (e) {
      _appendErr('Simulate Apply failed: $e');
      rethrow;
    }
  }

  Future<void> _resetAll() async {
    setState(() => _log = '');
    _appendLog('=== Reset All Consumer State ===');
    try {
      await ref.read(roomScanResultProvider.notifier).clear();
      _appendLog('roomScanResultProvider → cleared');
    } catch (e) {
      _appendErr('Clear room scan failed: $e');
    }
    try {
      // Snapshot IDs before modifying state
      final profileIds =
          ref.read(consumerSoundProfileProvider).map((p) => p.id).toList();
      await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
      for (final id in profileIds) {
        await ref.read(consumerSoundProfileProvider.notifier).delete(id);
      }
      _appendLog(
          'consumerSoundProfileProvider → cleared (${profileIds.length} profile(s) deleted)');
    } catch (e) {
      _appendErr('Clear profiles failed: $e');
    }
    try {
      ref.read(installLocationProvider.notifier).state = null;
      _appendLog('installLocationProvider → null');
    } catch (e) {
      _appendErr('Clear install location failed: $e');
    }
    await TunePlanStore.clear();
    await _refreshQaPairStatus();
    final afterScan = ref.read(roomScanResultProvider);
    final afterProfiles = ref.read(consumerSoundProfileProvider);
    final afterActive = ref.read(activeConsumerProfileProvider);
    _appendLog(
        'Verify after reset: scan=${afterScan == null ? "null ✓" : "still exists ✗"}, '
        'profiles=${afterProfiles.length} (${afterProfiles.isEmpty ? "empty ✓" : "not empty ✗"}), '
        'active=${afterActive == null ? "null ✓" : "still set ✗"}');
    _appendLog('=== Reset complete ===');
  }

  Future<void> _runFullFlow() async {
    setState(() => _log = '');
    _appendLog('=== Run Full Flow (A → F) ===');
    // Step 1: Reset previous state
    _appendLog('Step 1: Reset previous simulation state');
    try {
      await ref.read(roomScanResultProvider.notifier).clear();
      final profileIds =
          ref.read(consumerSoundProfileProvider).map((p) => p.id).toList();
      await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
      for (final id in profileIds) {
        await ref.read(consumerSoundProfileProvider.notifier).delete(id);
      }
      ref.read(installLocationProvider.notifier).state = null;
      await TunePlanStore.clear();
      _appendLog('Previous state cleared');
    } catch (e) {
      _appendErr('Reset failed: $e — continuing anyway');
    }
    // Step 2–5: Simulate each stage
    try {
      await _simulateInstallLocation();
      await _simulateRoomScan();
      await _simulateCreateTune();
      await _simulateApplyProfile();
    } catch (e) {
      _appendErr('Flow aborted at: $e');
      return;
    }
    // Final verification
    _appendLog('--- Final state verification ---');
    final scan = ref.read(roomScanResultProvider);
    final profiles = ref.read(consumerSoundProfileProvider);
    final active = ref.read(activeConsumerProfileProvider);
    final location = ref.read(installLocationProvider);
    _appendLog('installLocation: ${location?.labelEn ?? "null"}');
    _appendLog(
        'roomScan: ${scan?.roomType ?? "null"} (confidence: ${scan?.confidence ?? "-"})');
    _appendLog(
        'profiles: ${profiles.length} total, ${profiles.where((p) => p.isActive).length} active');
    _appendLog(
        'activeProfile: ${active?.name ?? "null"} (status: ${active?.status.name ?? "-"})');
    _appendLog(
        '=== Done. Navigate to TUNE → State F, LISTEN → ConsumerActiveView. ===');
    await _refreshQaPairStatus();
  }

  void _verifyCurrentState() {
    setState(() => _log = '');
    _appendLog('=== Verify Current App State ===');
    final scan = ref.read(roomScanResultProvider);
    final profiles = ref.read(consumerSoundProfileProvider);
    final active = ref.read(activeConsumerProfileProvider);
    final location = ref.read(installLocationProvider);
    final ble = ref.read(bleProvider);

    _appendLog('BLE: ${ble.connection.name}');
    _appendLog('installLocation: ${location?.labelEn ?? "null (not set)"}');

    if (scan == null) {
      _appendLog('roomScan: null (no scan)');
    } else {
      _appendLog('roomScan: exists');
      _appendLog('  roomType: ${scan.roomType}');
      _appendLog('  confidence: ${scan.confidence}');
      _appendLog('  micProfile: ${scan.micProfileName}');
      _appendLog('  cards: ${scan.cards.length}');
    }

    _appendLog('soundProfiles: ${profiles.length} total');
    for (final p in profiles) {
      _appendLog('  [${p.status.name}] ${p.name} (active: ${p.isActive})');
    }

    if (active == null) {
      _appendLog('activeProfile: null (none set)');
    } else {
      _appendLog('activeProfile: "${active.name}"');
      _appendLog('  status: ${active.status.name}');
      _appendLog('  roomType: ${active.roomType}');
      _appendLog('  confidence: ${active.confidence}');
      _appendLog('  cards: ${active.resultCards.length}');
    }
    _appendLog('=== Verify complete ===');
  }

  Widget _physicalQaPanel() {
    final fixture = _physicalQaFixture!;
    final validated =
        ref.read(consumerBleServiceProvider).supportedIdentityValidated;
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.orangeAccent.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PHYSICAL ICP5 QA — ONE BAND',
            style: TextStyle(color: Colors.orangeAccent, fontSize: 10),
          ),
          _StatusRow(
            label: 'Device validation',
            value: validated ? 'validated' : 'not validated',
          ),
          _StatusRow(label: 'Channel', value: '${fixture.channel}'),
          _StatusRow(label: 'Band', value: '${fixture.bandId + 1}'),
          _StatusRow(
            label: 'Original F / Gain / Q',
            value: '${fixture.originalFrequencyHz} Hz / '
                '${fixture.originalGainDb?.toStringAsFixed(1) ?? "required"} dB / '
                '${fixture.originalQ.toStringAsFixed(1)}',
          ),
          _StatusRow(
            label: 'Test F / Gain / Q',
            value: '${fixture.testFrequencyHz} Hz / '
                '${fixture.testGainDb?.toStringAsFixed(1) ?? "pending"} dB / '
                '${fixture.testQ.toStringAsFixed(1)}',
          ),
          Text(
            'Evidence: ${fixture.evidenceSource}',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _originalGainController,
            keyboardType: const TextInputType.numberWithOptions(
              signed: true,
              decimal: true,
            ),
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Original Gain from current physical DSP (dB)',
              labelStyle: TextStyle(color: Colors.white54, fontSize: 10),
            ),
            onChanged: (value) => setState(() {
              _physicalQaFixture = fixture.withOriginalGain(
                double.tryParse(value.trim()),
              );
            }),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: fixture.snapshotConfirmed,
            onChanged: fixture.originalGainDb == null
                ? null
                : (value) => setState(() {
                      _physicalQaFixture =
                          fixture.withSnapshotConfirmation(value ?? false);
                    }),
            title: const Text(
              'I confirmed these original values match the current physical DSP state.',
              style: TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ),
          _StatusRow(
            label: 'Snapshot complete',
            value: fixture.snapshotComplete ? 'yes' : 'no',
          ),
        ],
      ),
    );
  }

  Widget _qaPairPanel() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PERSISTED QA PAIR',
              style: TextStyle(color: Colors.white54, fontSize: 10),
            ),
            _StatusRow(
              label: 'Stored TunePlan ID',
              value: _qaPairStatus.storedTunePlanId ?? 'missing',
            ),
            _StatusRow(
              label: 'Selected profile ID',
              value: _qaPairStatus.selectedProfileId ?? 'missing',
            ),
            _StatusRow(
              label: 'Selected profile TunePlan ID',
              value: _qaPairStatus.selectedProfileTunePlanId ?? 'missing',
            ),
            _StatusRow(
              label: 'Match',
              value: _qaPairStatus.matches ? 'yes' : 'no',
            ),
            _StatusRow(
              label: 'Block reason',
              value: _qaPairStatus.blockReason,
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(roomScanResultProvider);
    final profiles = ref.watch(consumerSoundProfileProvider);
    final active = ref.watch(activeConsumerProfileProvider);
    final ble = ref.watch(bleProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF080C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080C10),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white54),
        title: const Text(
          'DEV SIMULATION',
          style: TextStyle(
              color: Color(0xFF4A9EFF), fontSize: 13, letterSpacing: 2),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // State panel
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('LIVE STATE',
                        style: TextStyle(
                            color: Colors.white24,
                            fontSize: 9,
                            letterSpacing: 2)),
                    const SizedBox(height: 6),
                    _StatusRow(label: 'BLE', value: ble.connection.name),
                    _StatusRow(
                        label: 'Room Scan',
                        value: scan != null
                            ? '${scan.roomType} (${scan.confidence})'
                            : 'none'),
                    _StatusRow(
                        label: 'Profiles',
                        value:
                            '${profiles.length} total, ${profiles.where((p) => p.isActive).length} active'),
                    _StatusRow(
                        label: 'Active Profile', value: active?.name ?? 'none'),
                  ]),
            ),
            const SizedBox(height: 12),

            // Action buttons
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _DevButton(
                    label: 'Run Full Flow (A→F)',
                    color: const Color(0xFF4A9EFF),
                    onTap: _runFullFlow,
                  ),
                  const SizedBox(height: 8),
                  _DevButton(
                      label: 'Verify Current State',
                      color: const Color(0xFFFFD700),
                      onTap: _verifyCurrentState),
                  if (_physicalQaFixture != null) _physicalQaPanel(),
                  if (_physicalQaFixture != null) _qaPairPanel(),
                  if (_physicalQaFixture != null)
                    _DevButton(
                      label: 'Prepare Physical QA Profile + TunePlan',
                      color: const Color(0xFF22C55E),
                      onTap: _simulateCreateTune,
                    ),
                  _DevButton(
                    key: const ValueKey('apply_dsp_test'),
                    label: 'Apply DSP Test',
                    color: const Color(0xFFFF8A00),
                    onTap: _applyDspTest,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'DSP TEST: $_dspStatus',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.black,
                    child: Text(
                      _dspResultDetails,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    ),
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  _DevButton(
                      label: 'Set Install Location (Living Room)',
                      onTap: _simulateInstallLocation),
                  _DevButton(
                      label: 'Simulate Room Scan', onTap: _simulateRoomScan),
                  _DevButton(
                      label: 'Simulate Acoustic Tune creation',
                      onTap: _simulateCreateTune),
                  _DevButton(
                      label: 'Simulate Apply Sound Profile',
                      onTap: _simulateApplyProfile),
                  const Divider(color: Colors.white12, height: 24),
                  _DevButton(
                      label: 'Reset All Consumer State',
                      color: Colors.redAccent,
                      onTap: _resetAll),
                  const SizedBox(height: 16),

                  // Log output
                  if (_log.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        _log,
                        style: const TextStyle(
                            color: Color(0xFF22C55E),
                            fontSize: 11,
                            fontFamily: 'monospace',
                            height: 1.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Text('$label: ',
              style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(color: Colors.white70, fontSize: 11))),
        ]),
      );
}

class _DevButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _DevButton({
    super.key,
    required this.label,
    required this.onTap,
    this.color = Colors.white54,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: color.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: TextStyle(color: color, fontSize: 13)),
        ),
      );
}
