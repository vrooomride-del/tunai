// Speaker Verification session state — ties the audio Speaker Check
// confirmation to a specific speaker identity + BLE connection generation so
// it survives ROOM → TUNE → APPLY navigation on the same connection, but
// auto-invalidates on disconnect, reconnect, or a different speaker.
//
// Exercises isSpeakerVerificationRecordValid directly (a pure function of
// SpeakerVerificationRecord + BleState) rather than going through the real
// bleProvider/BleController — BleController's constructor kicks off real
// platform-channel BLE init that hangs/throws with no device bindings in a
// plain test environment (the same class of limitation documented for
// AudioPlayer in splash_screen_test.dart).

import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/speaker_verification_session.dart';
import 'package:tunai/features/ble/ble_controller.dart';

final _confirmedAt = DateTime.fromMillisecondsSinceEpoch(1000);

SpeakerVerificationRecord _record({
  String speakerId = 'spk-1',
  int connectionGeneration = 1,
}) =>
    SpeakerVerificationRecord(
      speakerId: speakerId,
      connectionGeneration: connectionGeneration,
      confirmedAt: _confirmedAt,
    );

BleState _connected({
  String? deviceId = 'spk-1',
  int connectionGeneration = 1,
}) =>
    BleState(
      connection: BleConnectionState.connected,
      selectedDeviceIdentifier: deviceId,
      connectionGeneration: connectionGeneration,
    );

void main() {
  test('matching speaker + generation + connected → valid', () {
    expect(
      isSpeakerVerificationRecordValid(_record(), _connected()),
      isTrue,
    );
  });

  test('no record at all → never valid', () {
    expect(
      isSpeakerVerificationRecordValid(null, _connected()),
      isFalse,
    );
  });

  test('disconnected (even with matching identity/generation) → invalid', () {
    final ble = _connected().copyWith(connection: BleConnectionState.disconnected);
    expect(isSpeakerVerificationRecordValid(_record(), ble), isFalse);
  });

  test('reconnect to the SAME speaker but a NEW connection generation → invalid',
      () {
    final ble = _connected(connectionGeneration: 2);
    expect(
      isSpeakerVerificationRecordValid(
          _record(connectionGeneration: 1), ble),
      isFalse,
    );
  });

  test('different speaker identifier → invalid', () {
    final ble = _connected(deviceId: 'spk-2');
    expect(
      isSpeakerVerificationRecordValid(_record(speakerId: 'spk-1'), ble),
      isFalse,
    );
  });

  test('no selected device identifier at all → invalid', () {
    final ble = _connected(deviceId: null);
    expect(isSpeakerVerificationRecordValid(_record(), ble), isFalse);
  });

  test('BleState.copyWith increments connectionGeneration only when told to, '
      'and leaves it untouched on unrelated state churn', () {
    var state = const BleState();
    expect(state.connectionGeneration, 0);

    // Mirrors what BleController._onServiceChanged does on a fresh connect.
    state = state.copyWith(
      connection: BleConnectionState.connected,
      connectionGeneration: state.connectionGeneration + 1,
    );
    expect(state.connectionGeneration, 1);

    // Unrelated churn (e.g. isSending toggling) must not bump generation.
    state = state.copyWith(isSending: true);
    expect(state.connectionGeneration, 1);
  });
}
