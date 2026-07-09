// ── Developer / QA Simulation Screen ─────────────────────────────────────────
// Access: FACTORY MODE (PIN 1234) → "Developer Simulation" button.
// NOT accessible from the normal consumer flow.
// Simulates the full consumer state machine without real hardware:
//   connected → roomSelected → roomScanCompleted
//   → acousticTuneCreated → soundProfileActive → listenReady
// No real DSP writes, no real BLE, no real microphone input.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/room_scan_result.dart';
import '../../core/consumer_sound_profile.dart';
import '../../core/install_location.dart';

class DevSimulationScreen extends ConsumerStatefulWidget {
  const DevSimulationScreen({super.key});

  @override
  ConsumerState<DevSimulationScreen> createState() => _DevSimulationScreenState();
}

class _DevSimulationScreenState extends ConsumerState<DevSimulationScreen> {
  String _log = '';

  void _appendLog(String msg) => setState(() => _log += '✓ $msg\n');

  Future<void> _simulateRoomScan() async {
    _appendLog('Simulating Room Scan...');
    await Future.delayed(const Duration(milliseconds: 600));
    final result = RoomScanResult(
      roomType: 'Living Room',
      micProfileName: 'Generic (Simulation)',
      completedAt: DateTime.now(),
      confidence: 'High',
      cards: kDefaultResultCards.toList(),
    );
    await ref.read(roomScanResultProvider.notifier).saveResult(result);
    _appendLog('roomScanResultProvider → saved (Living Room, 4 cards)');
  }

  Future<void> _simulateCreateTune() async {
    final scan = ref.read(roomScanResultProvider);
    if (scan == null) {
      setState(() => _log += '✗ No room scan — run "Simulate Room Scan" first\n');
      return;
    }
    _appendLog('Simulating Acoustic Tune creation...');
    await Future.delayed(const Duration(milliseconds: 500));
    final profile = ConsumerSoundProfile(
      id: 'sim_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Living Room Acoustic Tune (SIM)',
      roomType: scan.roomType,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      micProfileName: scan.micProfileName,
      confidence: scan.confidence,
      isActive: false,
      status: ConsumerProfileStatus.ready,
      resultCards: scan.cards,
    );
    await ref.read(consumerSoundProfileProvider.notifier).add(profile);
    _appendLog('consumerSoundProfileProvider → added (status: ready)');
  }

  Future<void> _simulateApplyProfile() async {
    final profiles = ref.read(consumerSoundProfileProvider);
    final ready = profiles.where((p) => p.status == ConsumerProfileStatus.ready).toList();
    if (ready.isEmpty) {
      setState(() => _log += '✗ No ready profile — run "Simulate Acoustic Tune" first\n');
      return;
    }
    _appendLog('Simulating Sound Profile apply...');
    await Future.delayed(const Duration(milliseconds: 300));
    await ref.read(consumerSoundProfileProvider.notifier).setActive(ready.first.id);
    _appendLog('activeConsumerProfileProvider → "${ready.first.name}" is now active');
    _appendLog('State F (listenReady) should now be visible in TUNE tab');
  }

  Future<void> _simulateInstallLocation() async {
    ref.read(installLocationProvider.notifier).state = InstallLocation.livingRoom;
    _appendLog('installLocationProvider → Living Room');
  }

  Future<void> _resetAll() async {
    await ref.read(roomScanResultProvider.notifier).clear();
    await ref.read(consumerSoundProfileProvider.notifier).deactivateAll();
    // Delete all profiles
    final profiles = ref.read(consumerSoundProfileProvider);
    for (final p in profiles) {
      await ref.read(consumerSoundProfileProvider.notifier).delete(p.id);
    }
    ref.read(installLocationProvider.notifier).state = null;
    setState(() => _log = '');
    _appendLog('All consumer state reset to initial.');
  }

  Future<void> _runFullFlow() async {
    setState(() => _log = '');
    _appendLog('=== Full consumer flow simulation ===');
    await _simulateInstallLocation();
    await _simulateRoomScan();
    await _simulateCreateTune();
    await _simulateApplyProfile();
    _appendLog('=== Done. Open TUNE tab → state F, LISTEN tab → ConsumerActiveView. ===');
  }

  @override
  Widget build(BuildContext context) {
    final scan = ref.watch(roomScanResultProvider);
    final profiles = ref.watch(consumerSoundProfileProvider);
    final active = ref.watch(activeConsumerProfileProvider);

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
            // Status row
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('STATE', style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
                const SizedBox(height: 6),
                _StatusRow(label: 'Room Scan', value: scan != null ? scan.roomType : 'none'),
                _StatusRow(label: 'Profiles', value: '${profiles.length} (${profiles.where((p) => p.isActive).length} active)'),
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
      Text(value, style: const TextStyle(color: Colors.white70, fontSize: 11)),
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
