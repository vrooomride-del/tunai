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
import '../ble/ble_controller.dart';

class DevSimulationScreen extends ConsumerStatefulWidget {
  const DevSimulationScreen({super.key});

  @override
  ConsumerState<DevSimulationScreen> createState() => _DevSimulationScreenState();
}

class _DevSimulationScreenState extends ConsumerState<DevSimulationScreen> {
  String _log = '';

  void _appendLog(String msg) => setState(() => _log += '✓ $msg\n');
  void _appendErr(String msg) => setState(() => _log += '✗ $msg\n');

  Future<void> _simulateInstallLocation() async {
    try {
      _appendLog('Set Install Location → Living Room');
      ref.read(installLocationProvider.notifier).state = InstallLocation.livingRoom;
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
        _appendErr('roomScanResultProvider → null after save (persistence error)');
      } else {
        _appendLog('roomScanResultProvider → saved (${verify.roomType}, ${verify.cards.length} cards)');
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
      _appendLog('Simulate Acoustic Tune creation started...');
      await Future.delayed(const Duration(milliseconds: 400));
      final profile = ConsumerSoundProfile(
        id: 'sim_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Living Room Acoustic Tune',
        roomType: scan.roomType,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        micProfileName: scan.micProfileName,
        confidence: scan.confidence,
        isActive: false,
        status: ConsumerProfileStatus.ready,
        resultCards: scan.cards,
        soundScoreBefore: 82,
        soundScoreAfter: 94,
        profileType: ConsumerProfileType.tunaiTune,
      );
      await ref.read(consumerSoundProfileProvider.notifier).add(profile);
      final profiles = ref.read(consumerSoundProfileProvider);
      _appendLog('consumerSoundProfileProvider → ${profiles.length} profile(s), latest: ${profiles.first.name} (status: ready)');
    } catch (e) {
      _appendErr('Simulate Create Tune failed: $e');
      rethrow;
    }
  }

  Future<void> _simulateApplyProfile() async {
    try {
      final profiles = ref.read(consumerSoundProfileProvider);
      final ready = profiles.where((p) => p.status == ConsumerProfileStatus.ready).toList();
      if (ready.isEmpty) {
        _appendErr('No ready profile — run Simulate Acoustic Tune first');
        return;
      }
      _appendLog('Simulate Apply Sound Profile: "${ready.first.name}"');
      await ref.read(consumerSoundProfileProvider.notifier).setActive(ready.first.id);
      final active = ref.read(activeConsumerProfileProvider);
      if (active == null) {
        _appendErr('activeConsumerProfileProvider → null after setActive (unexpected)');
      } else {
        _appendLog('activeConsumerProfileProvider → "${active.name}" (status: ${active.status.name})');
        _appendLog('TUNE tab should now show State F. LISTEN tab shows ConsumerActiveView.');
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
      final profileIds = ref.read(consumerSoundProfileProvider).map((p) => p.id).toList();
      await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
      for (final id in profileIds) {
        await ref.read(consumerSoundProfileProvider.notifier).delete(id);
      }
      _appendLog('consumerSoundProfileProvider → cleared (${profileIds.length} profile(s) deleted)');
    } catch (e) {
      _appendErr('Clear profiles failed: $e');
    }
    try {
      ref.read(installLocationProvider.notifier).state = null;
      _appendLog('installLocationProvider → null');
    } catch (e) {
      _appendErr('Clear install location failed: $e');
    }
    final afterScan = ref.read(roomScanResultProvider);
    final afterProfiles = ref.read(consumerSoundProfileProvider);
    final afterActive = ref.read(activeConsumerProfileProvider);
    _appendLog('Verify after reset: scan=${afterScan == null ? "null ✓" : "still exists ✗"}, '
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
      final profileIds = ref.read(consumerSoundProfileProvider).map((p) => p.id).toList();
      await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
      for (final id in profileIds) {
        await ref.read(consumerSoundProfileProvider.notifier).delete(id);
      }
      ref.read(installLocationProvider.notifier).state = null;
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
    _appendLog('roomScan: ${scan?.roomType ?? "null"} (confidence: ${scan?.confidence ?? "-"})');
    _appendLog('profiles: ${profiles.length} total, ${profiles.where((p) => p.isActive).length} active');
    _appendLog('activeProfile: ${active?.name ?? "null"} (status: ${active?.status.name ?? "-"})');
    _appendLog('=== Done. Navigate to TUNE → State F, LISTEN → ConsumerActiveView. ===');
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
          style: TextStyle(color: Color(0xFF4A9EFF), fontSize: 13, letterSpacing: 2),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIVE STATE', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
                const SizedBox(height: 6),
                _StatusRow(label: 'BLE', value: ble.connection.name),
                _StatusRow(label: 'Room Scan', value: scan != null ? '${scan.roomType} (${scan.confidence})' : 'none'),
                _StatusRow(label: 'Profiles', value: '${profiles.length} total, ${profiles.where((p) => p.isActive).length} active'),
                _StatusRow(label: 'Active Profile', value: active?.name ?? 'none'),
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
                  _DevButton(label: 'Verify Current State', color: const Color(0xFFFFD700), onTap: _verifyCurrentState),
                  const Divider(color: Colors.white12, height: 24),
                  _DevButton(label: 'Set Install Location (Living Room)', onTap: _simulateInstallLocation),
                  _DevButton(label: 'Simulate Room Scan', onTap: _simulateRoomScan),
                  _DevButton(label: 'Simulate Acoustic Tune creation', onTap: _simulateCreateTune),
                  _DevButton(label: 'Simulate Apply Sound Profile', onTap: _simulateApplyProfile),
                  const Divider(color: Colors.white12, height: 24),
                  _DevButton(label: 'Reset All Consumer State', color: Colors.redAccent, onTap: _resetAll),
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
                        style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11,
                            fontFamily: 'monospace', height: 1.6),
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
      Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 11)),
      Expanded(child: Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11))),
    ]),
  );
}

class _DevButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _DevButton({required this.label, required this.onTap, this.color = Colors.white54});

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
