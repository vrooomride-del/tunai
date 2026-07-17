import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/consumer_dsp_deployment.dart';
import 'package:tunai/core/dsp_state_synchronization.dart';
import 'package:tunai/core/speaker_state_verification.dart';

// ── Fixtures ─────────────────────────────────────────────────────────────────

const _kSpeakerId = 'tunai-one-A1B2C3';
final _kNow = DateTime.utc(2025, 7, 1, 12);

const _kBand0 = DspPeqStateRequest(channel: 1, bandId: 0);
const _kBand1 = DspPeqStateRequest(channel: 1, bandId: 1);
const _kRequiredStates = [_kBand0, _kBand1];

DspStateSnapshot _snapshot({String speakerId = _kSpeakerId}) =>
    DspStateSnapshot(
      deviceIdentifier: speakerId,
      capturedAt: DateTime.utc(2025, 7, 1, 11, 55),
      peqStates: const [
        DspPeqState(
          channel: 1,
          bandId: 0,
          frequencyHz: 1800,
          gainDb: -1.0,
          q: 2.0,
          enabled: true,
        ),
        DspPeqState(
          channel: 1,
          bandId: 1,
          frequencyHz: 500,
          gainDb: 0.5,
          q: 1.5,
          enabled: true,
        ),
      ],
    );

// ── Fake transport ────────────────────────────────────────────────────────────

class _FakeTransport implements ConsumerDspTransport {
  @override
  final bool connected;
  @override
  final bool handshakeValidated;
  @override
  final String? deviceIdentifier;

  const _FakeTransport({
    this.connected = true,
    this.handshakeValidated = true,
    this.deviceIdentifier = _kSpeakerId,
  });

  @override
  Future<List<int>> writeAndAwaitResponse(List<int> command,
      {required Duration timeout}) async => const [];
}

// ── Helper ────────────────────────────────────────────────────────────────────

SpeakerCheckResult _check({
  _FakeTransport? transport,
  String expectedSpeakerId = _kSpeakerId,
  List<DspPeqStateRequest> requiredStates = _kRequiredStates,
  DspStateSnapshot? snapshot,
  bool includeSnapshot = true,
}) =>
    SpeakerStateVerification.evaluate(
      transport: transport ?? const _FakeTransport(),
      expectedSpeakerId: expectedSpeakerId,
      requiredStates: requiredStates,
      snapshot: includeSnapshot ? (snapshot ?? _snapshot()) : null,
      clock: () => _kNow,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('SpeakerStateVerification — verified speaker', () {
    test('all conditions met → readyToApply', () {
      final result = _check();
      expect(result.readyToApply, isTrue);
      expect(result.status, SpeakerCheckStatus.readyToApply);
      expect(result.confirmedSpeakerId, _kSpeakerId);
      expect(result.evaluatedAt, _kNow);
      expect(result.missingStateReasons, isEmpty);
    });

    test('confirmedSpeakerId is populated on pass', () {
      final result = _check();
      expect(result.confirmedSpeakerId, _kSpeakerId);
    });

    test('missingStateReasons is empty on pass', () {
      expect(_check().missingStateReasons, isEmpty);
    });
  });

  group('SpeakerStateVerification — disconnected speaker', () {
    test('not connected → speakerNotConnected', () {
      final result = _check(
        transport: const _FakeTransport(connected: false),
      );
      expect(result.readyToApply, isFalse);
      expect(result.status, SpeakerCheckStatus.speakerNotConnected);
      expect(result.confirmedSpeakerId, isNull);
    });

    test('disconnected takes priority over missing snapshot', () {
      final result = _check(
        transport: const _FakeTransport(connected: false),
        includeSnapshot: false,
      );
      expect(result.status, SpeakerCheckStatus.speakerNotConnected);
    });
  });

  group('SpeakerStateVerification — invalid identity', () {
    test('handshake not validated → identityUnconfirmed', () {
      final result = _check(
        transport: const _FakeTransport(handshakeValidated: false),
      );
      expect(result.readyToApply, isFalse);
      expect(result.status, SpeakerCheckStatus.identityUnconfirmed);
      expect(result.confirmedSpeakerId, isNull);
    });

    test('device identifier does not match expected → speakerMismatch', () {
      final result = _check(
        transport: const _FakeTransport(deviceIdentifier: 'tunai-one-ZZZZZZ'),
      );
      expect(result.readyToApply, isFalse);
      expect(result.status, SpeakerCheckStatus.speakerMismatch);
    });

    test('null device identifier → speakerMismatch', () {
      final result = _check(
        transport: const _FakeTransport(deviceIdentifier: null),
      );
      expect(result.status, SpeakerCheckStatus.speakerMismatch);
    });

    test('empty expectedSpeakerId → speakerMismatch', () {
      final result = _check(expectedSpeakerId: '');
      expect(result.status, SpeakerCheckStatus.speakerMismatch);
    });
  });

  group('SpeakerStateVerification — missing original state', () {
    test('no snapshot → soundStateNotVerified', () {
      final result = _check(includeSnapshot: false);
      expect(result.readyToApply, isFalse);
      expect(result.status, SpeakerCheckStatus.soundStateNotVerified);
      expect(result.missingStateReasons, isNotEmpty);
    });

    test('snapshot covers only subset of required bands → originalValuesUnavailable',
        () {
      final partial = DspStateSnapshot(
        deviceIdentifier: _kSpeakerId,
        capturedAt: DateTime.utc(2025, 7, 1, 11, 55),
        peqStates: const [
          DspPeqState(
            channel: 1,
            bandId: 0,
            frequencyHz: 1800,
            gainDb: -1.0,
            q: 2.0,
            enabled: true,
          ),
          // band 1 is missing
        ],
      );

      final result = _check(snapshot: partial);
      expect(result.readyToApply, isFalse);
      expect(result.status, SpeakerCheckStatus.originalValuesUnavailable);
      expect(result.missingStateReasons, isNotEmpty);
      expect(result.missingStateReasons.any((r) => r.contains('Band 1')), isTrue);
    });

    test('snapshot from a different speaker → originalValuesUnavailable', () {
      final wrong = _snapshot(speakerId: 'tunai-one-WRONG');
      final result = _check(snapshot: wrong);
      expect(result.readyToApply, isFalse);
      expect(result.status, SpeakerCheckStatus.originalValuesUnavailable);
    });
  });

  group('SpeakerStateVerification — restart does not falsely claim verified', () {
    test('toPersistedState always returns notVerified', () {
      final verified = _check();
      expect(verified.readyToApply, isTrue);
      expect(verified.toPersistedState(),
          SpeakerCheckPersistedState.notVerified);
    });

    test('blocked result also serialises as notVerified', () {
      final blocked = _check(transport: const _FakeTransport(connected: false));
      expect(blocked.toPersistedState(),
          SpeakerCheckPersistedState.notVerified);
    });

    test('persisted state enum has only safe value', () {
      const values = SpeakerCheckPersistedState.values;
      expect(values, hasLength(1));
      expect(values.single, SpeakerCheckPersistedState.notVerified);
    });

    test('re-evaluating after simulated restart without snapshot is not ready',
        () {
      // Simulate: verified in session, app restarted, no snapshot available.
      final afterRestart = _check(includeSnapshot: false);
      expect(afterRestart.readyToApply, isFalse);
    });
  });

  group('SpeakerStateVerification — evaluatedAt clock', () {
    test('evaluatedAt reflects the clock value', () {
      final ts = DateTime.utc(2025, 12, 31, 23, 59);
      final result = SpeakerStateVerification.evaluate(
        transport: const _FakeTransport(),
        expectedSpeakerId: _kSpeakerId,
        requiredStates: _kRequiredStates,
        snapshot: _snapshot(),
        clock: () => ts,
      );
      expect(result.evaluatedAt, ts);
    });
  });
}
