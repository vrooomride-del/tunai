import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/ble/ble_controller.dart';
import 'consumer_dsp_deployment.dart';
import 'dsp_state_synchronization.dart';
import 'speaker_state_verification.dart';

// ── Required-states constant ─────────────────────────────────────────────────
//
// Consumer tune plans use channel 1, bands 0–2 (up to 3 bands).
// The gate requests all three so any snapshot that covers the active plan
// necessarily covers this superset.

const _kRequiredStates = [
  DspPeqStateRequest(channel: 1, bandId: 0),
  DspPeqStateRequest(channel: 1, bandId: 1),
  DspPeqStateRequest(channel: 1, bandId: 2),
];

// ── Snapshot provider ─────────────────────────────────────────────────────────

/// Holds the most-recent verified DSP state snapshot.
///
/// Starts null and is never auto-populated: no read protocol is implemented
/// yet.  Future read capability should update this provider after a successful
/// device read.
final dspStateSnapshotProvider = StateProvider<DspStateSnapshot?>((ref) => null);

// ── Speaker check result provider ────────────────────────────────────────────

/// Derives the current [SpeakerCheckResult] from BLE state and snapshot.
///
/// Recomputes whenever the BLE connection state or snapshot changes.
/// The result is session-scoped — it is never persisted as "verified".
final speakerCheckResultProvider = Provider<SpeakerCheckResult>((ref) {
  final ble = ref.watch(bleProvider);
  final snapshot = ref.watch(dspStateSnapshotProvider);
  final service = ref.read(consumerBleServiceProvider);
  final transport = ConsumerBleDspTransport(service);
  final expectedId = ble.selectedDeviceIdentifier ?? '';

  return SpeakerStateVerification.evaluate(
    transport: transport,
    expectedSpeakerId: expectedId,
    requiredStates: _kRequiredStates,
    snapshot: snapshot,
  );
});

// ── Persisted state provider ──────────────────────────────────────────────────

/// Always returns [SpeakerCheckPersistedState.notVerified].
///
/// A verified Speaker Check from a previous session must never be restored
/// as still valid.  Callers must re-evaluate after every restart or reconnect.
final speakerCheckPersistedStateProvider =
    Provider<SpeakerCheckPersistedState>(
  (_) => SpeakerCheckPersistedState.notVerified,
);
