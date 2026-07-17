import 'consumer_dsp_deployment.dart';
import 'dsp_state_synchronization.dart';

// ── Consumer-facing status ────────────────────────────────────────────────────

/// Consumer-visible outcome of a Speaker Check.
///
/// All values use product terminology.  No DSP addresses, packets, or internal
/// transport concepts are exposed through this enum.
enum SpeakerCheckStatus {
  /// All conditions met — the app is ready to apply a Sound Profile.
  readyToApply,

  /// The speaker is not connected via Bluetooth.
  speakerNotConnected,

  /// The speaker's identity could not be confirmed in this session.
  identityUnconfirmed,

  /// The connected speaker does not match the expected speaker.
  speakerMismatch,

  /// Sound state has not been verified for this session.
  /// Original values have not been obtained yet.
  soundStateNotVerified,

  /// Sound state was partially obtained but required values are absent.
  originalValuesUnavailable,
}

// ── Persistence-safe session flag ─────────────────────────────────────────────

/// Persisted marker for the Speaker Check result.
///
/// Only [notVerified] is safe to store.  A previous-session verified result
/// must never be treated as still valid; the app must re-run the Speaker Check
/// after every restart or reconnect.
enum SpeakerCheckPersistedState {
  /// Default — no verification has been completed in this session.
  notVerified,
}

// ── Verification result ───────────────────────────────────────────────────────

/// Immutable result of one Speaker Check evaluation.
///
/// Callers read [readyToApply] before enabling the Apply action.
/// The result is session-scoped: it must be discarded on disconnect or restart.
class SpeakerCheckResult {
  /// Outcome of the Speaker Check.
  final SpeakerCheckStatus status;

  /// The speaker identifier that was confirmed during this session.
  /// Present only when the identity handshake succeeded.
  final String? confirmedSpeakerId;

  /// When this check was evaluated.
  final DateTime evaluatedAt;

  /// Consumer-readable reasons why required original values are absent.
  /// Empty when [status] is [SpeakerCheckStatus.readyToApply].
  final List<String> missingStateReasons;

  const SpeakerCheckResult._({
    required this.status,
    required this.evaluatedAt,
    this.confirmedSpeakerId,
    this.missingStateReasons = const [],
  });

  /// True only when all conditions are met and Apply may proceed.
  bool get readyToApply => status == SpeakerCheckStatus.readyToApply;

  /// Constructs a passing result.
  factory SpeakerCheckResult.verified({
    required String speakerId,
    required DateTime evaluatedAt,
  }) =>
      SpeakerCheckResult._(
        status: SpeakerCheckStatus.readyToApply,
        confirmedSpeakerId: speakerId,
        evaluatedAt: evaluatedAt,
      );

  /// Constructs a blocking result.
  factory SpeakerCheckResult.blocked({
    required SpeakerCheckStatus status,
    required DateTime evaluatedAt,
    List<String> missingStateReasons = const [],
  }) =>
      SpeakerCheckResult._(
        status: status,
        evaluatedAt: evaluatedAt,
        missingStateReasons: List.unmodifiable(missingStateReasons),
      );

  /// Returns the persistence-safe form of this result.
  ///
  /// Always [SpeakerCheckPersistedState.notVerified] — a verified check from
  /// a previous session must never be restored as still valid.
  SpeakerCheckPersistedState toPersistedState() =>
      SpeakerCheckPersistedState.notVerified;
}

// ── Verification service ──────────────────────────────────────────────────────

/// Evaluates whether the connected speaker is ready for a Sound Profile Apply.
///
/// This class is side-effect-free: it reads existing state and returns a
/// result.  It never writes to the device and never invents state.
///
/// Terminology is consumer-only.  Internal transport details, DSP addresses,
/// and packet structures are not exposed through the public API.
abstract final class SpeakerStateVerification {
  /// Evaluates the current speaker state against [expectedSpeakerId] and the
  /// required original values tracked by [snapshot].
  ///
  /// [transport] provides connectivity and identity facts.
  /// [requiredStates] lists the PEQ bands whose original values must exist
  ///   before Apply is permitted (internal concept, not exposed to callers).
  /// [snapshot] is the most-recent verified state read; may be null if no
  ///   read has succeeded in this session.
  /// [clock] is injectable for deterministic testing.
  static SpeakerCheckResult evaluate({
    required ConsumerDspTransport transport,
    required String expectedSpeakerId,
    required List<DspPeqStateRequest> requiredStates,
    required DspStateSnapshot? snapshot,
    DateTime Function()? clock,
  }) {
    final now = (clock ?? DateTime.now)();

    if (!transport.connected) {
      return SpeakerCheckResult.blocked(
        status: SpeakerCheckStatus.speakerNotConnected,
        evaluatedAt: now,
      );
    }

    if (!transport.handshakeValidated) {
      return SpeakerCheckResult.blocked(
        status: SpeakerCheckStatus.identityUnconfirmed,
        evaluatedAt: now,
      );
    }

    if (expectedSpeakerId.isEmpty ||
        transport.deviceIdentifier != expectedSpeakerId) {
      return SpeakerCheckResult.blocked(
        status: SpeakerCheckStatus.speakerMismatch,
        evaluatedAt: now,
      );
    }

    if (snapshot == null) {
      return SpeakerCheckResult.blocked(
        status: SpeakerCheckStatus.soundStateNotVerified,
        evaluatedAt: now,
        missingStateReasons: const ['No sound state has been obtained yet.'],
      );
    }

    // Snapshot must belong to the expected speaker and cover all required bands.
    if (snapshot.deviceIdentifier != expectedSpeakerId ||
        !snapshot.covers(requiredStates)) {
      final missing = requiredStates
          .where((r) => snapshot.stateFor(r) == null)
          .map((r) => 'Band ${r.bandId} (channel ${r.channel})')
          .toList();
      return SpeakerCheckResult.blocked(
        status: SpeakerCheckStatus.originalValuesUnavailable,
        evaluatedAt: now,
        missingStateReasons: missing,
      );
    }

    return SpeakerCheckResult.verified(
      speakerId: expectedSpeakerId,
      evaluatedAt: now,
    );
  }
}
