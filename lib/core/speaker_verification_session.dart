import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/ble/ble_controller.dart';

/// Session-scoped record of the user's audio Speaker Check confirmation —
/// "did the user confirm hearing the confirmation tone from THIS speaker, on
/// THIS specific connection". In-memory only (never persisted): a
/// confirmation from a previous app run must never be treated as still
/// valid, matching [SpeakerCheckPersistedState]'s existing policy in
/// speaker_state_verification.dart.
///
/// [connectionGeneration] ties the confirmation to one specific BLE
/// connection instance (see [BleState.connectionGeneration]) rather than
/// just the device identifier — a disconnect-and-reconnect to the exact
/// same speaker still invalidates it, because the phone's separate
/// Bluetooth AUDIO route (which the app cannot query or control — see
/// tunai_playback_audio_session.dart) may not have survived the drop.
class SpeakerVerificationRecord {
  final String speakerId;
  final int connectionGeneration;
  final DateTime confirmedAt;

  const SpeakerVerificationRecord({
    required this.speakerId,
    required this.connectionGeneration,
    required this.confirmedAt,
  });
}

class SpeakerVerificationSessionNotifier
    extends StateNotifier<SpeakerVerificationRecord?> {
  SpeakerVerificationSessionNotifier() : super(null);

  void confirmHeard({
    required String speakerId,
    required int connectionGeneration,
  }) {
    state = SpeakerVerificationRecord(
      speakerId: speakerId,
      connectionGeneration: connectionGeneration,
      confirmedAt: DateTime.now(),
    );
  }

  /// Explicit "아니요" (didn't hear it) or any other reason to withdraw the
  /// confirmation without waiting for BLE state to drift away from it.
  void clear() => state = null;
}

final speakerVerificationSessionProvider = StateNotifierProvider<
    SpeakerVerificationSessionNotifier, SpeakerVerificationRecord?>(
  (ref) => SpeakerVerificationSessionNotifier(),
);

/// Whether the stored confirmation record (if any) still matches the LIVE
/// BLE identity and connection generation — recomputed on every read, so a
/// disconnect, reconnect, or speaker swap invalidates it automatically
/// without needing a separate manual invalidation call at every place BLE
/// state can change.
bool isSpeakerVerificationRecordValid(
    SpeakerVerificationRecord? record, BleState ble) {
  if (record == null) return false;
  if (ble.connection != BleConnectionState.connected) return false;
  if (ble.selectedDeviceIdentifier == null) return false;
  return record.speakerId == ble.selectedDeviceIdentifier &&
      record.connectionGeneration == ble.connectionGeneration;
}

/// True only when the user's audio Speaker Check confirmation is still
/// valid for the currently-connected speaker and connection.
final audioSpeakerConfirmedProvider = Provider<bool>((ref) {
  final record = ref.watch(speakerVerificationSessionProvider);
  final ble = ref.watch(bleProvider);
  return isSpeakerVerificationRecordValid(record, ble);
});

/// True when a confirmation exists in memory but no longer matches live BLE
/// state (as opposed to never having been confirmed at all this session) —
/// used to choose between "스피커 연결이 변경되었습니다" (something changed)
/// and a plain "please confirm first" message.
final audioSpeakerConfirmationStaleProvider = Provider<bool>((ref) {
  final record = ref.watch(speakerVerificationSessionProvider);
  final ble = ref.watch(bleProvider);
  if (record == null) return false;
  return !isSpeakerVerificationRecordValid(record, ble);
});
