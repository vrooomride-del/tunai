// Tests for ProUsbiWindowsNativeBackend and ProUsbiNativeBackendDisabled.
//
// These tests run on macOS/Linux CI and confirm:
//   - Non-Windows returns unavailable immediately, no channel call.
//   - Disabled backend throws on all write calls.
//   - Fake backend's connect/disconnect logic.
//   - No fake success — connection state enforced before send methods.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tunai/core/pro_usbi_native_backend.dart';
import 'package:tunai/core/pro_usbi_windows_native_backend.dart';

void main() {
  // ── ProUsbiNativeBackend.createDefault() factory ─────────────────────────

  group('ProUsbiNativeBackend.createDefault()', () {
    test('returns Disabled on non-Windows', () {
      if (Platform.isWindows) return; // skip on actual Windows CI
      final backend = ProUsbiNativeBackend.createDefault();
      expect(backend, isA<ProUsbiNativeBackendDisabled>());
      expect(backend.status, UsbiBackendStatus.unavailable);
      expect(backend.isConnected, isFalse);
    });

    test('returns WindowsNativeBackend on Windows', () {
      if (!Platform.isWindows) return; // only runs on Windows CI
      final backend = ProUsbiNativeBackend.createDefault();
      expect(backend, isA<ProUsbiWindowsNativeBackend>());
    });
  });

  // ── ProUsbiWindowsNativeBackend — non-Windows guard ──────────────────────

  group('ProUsbiWindowsNativeBackend on non-Windows', () {
    late ProUsbiWindowsNativeBackend backend;

    setUp(() => backend = ProUsbiWindowsNativeBackend());

    test('checkAvailability returns unavailable without touching channel', () async {
      if (Platform.isWindows) return;
      final status = await backend.checkAvailability();
      expect(status, UsbiBackendStatus.unavailable);
      expect(backend.isConnected, isFalse);
      expect(backend.statusDetail, contains('Not Windows'));
    });

    test('openDevice returns unavailable on non-Windows', () async {
      if (Platform.isWindows) return;
      final status = await backend.openDevice();
      expect(status, UsbiBackendStatus.unavailable);
      expect(backend.isConnected, isFalse);
    });

    test('sendSetup throws when not connected', () async {
      if (Platform.isWindows) return;
      // isConnected is false — must throw without calling channel
      expect(
        () => backend.sendSetup([0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00]),
        throwsA(isA<UsbiTransportException>()),
      );
    });

    test('sendBody throws when not connected', () async {
      if (Platform.isWindows) return;
      expect(
        () => backend.sendBody([0x00, 0x67, 0x00, 0x80, 0x00, 0x00]),
        throwsA(isA<UsbiTransportException>()),
      );
    });

    test('readAck throws when not connected', () async {
      if (Platform.isWindows) return;
      expect(
        () => backend.readAck(),
        throwsA(isA<UsbiTransportException>()),
      );
    });

    test('closeDevice is safe to call when not connected', () async {
      // Should not throw
      await backend.closeDevice();
      expect(backend.isConnected, isFalse);
    });
  });

  // ── ProUsbiNativeBackendDisabled ──────────────────────────────────────────

  group('ProUsbiNativeBackendDisabled', () {
    const disabled = ProUsbiNativeBackendDisabled('test reason');

    test('status is unavailable', () {
      expect(disabled.status, UsbiBackendStatus.unavailable);
    });

    test('statusDetail contains reason', () {
      expect(disabled.statusDetail, contains('test reason'));
    });

    test('isConnected is false', () {
      expect(disabled.isConnected, isFalse);
    });

    test('checkAvailability returns unavailable', () async {
      expect(await disabled.checkAvailability(), UsbiBackendStatus.unavailable);
    });

    test('openDevice returns unavailable', () async {
      expect(await disabled.openDevice(), UsbiBackendStatus.unavailable);
    });

    test('closeDevice is a no-op', () async {
      await disabled.closeDevice(); // must not throw
    });

    test('sendSetup throws UsbiBackendUnavailableException', () async {
      expect(
        () => disabled.sendSetup([0x40, 0xB2]),
        throwsA(isA<UsbiBackendUnavailableException>()),
      );
    });

    test('sendBody throws UsbiBackendUnavailableException', () async {
      expect(
        () => disabled.sendBody([0x00, 0x67]),
        throwsA(isA<UsbiBackendUnavailableException>()),
      );
    });

    test('readAck throws UsbiBackendUnavailableException', () async {
      expect(
        () => disabled.readAck(),
        throwsA(isA<UsbiBackendUnavailableException>()),
      );
    });
  });

  // ── ProUsbiNativeBackendFake ──────────────────────────────────────────────

  group('ProUsbiNativeBackendFake', () {
    test('starts in pending state, not connected', () {
      final fake = ProUsbiNativeBackendFake();
      expect(fake.status, UsbiBackendStatus.pending);
      expect(fake.isConnected, isFalse);
    });

    test('simulateConnect sets connected + status', () {
      final fake = ProUsbiNativeBackendFake();
      fake.simulateConnect();
      expect(fake.isConnected, isTrue);
      expect(fake.status, UsbiBackendStatus.connected);
    });

    test('sendSetup fails before connect', () async {
      final fake = ProUsbiNativeBackendFake();
      expect(
        () => fake.sendSetup([0x40]),
        throwsA(isA<UsbiTransportException>()),
      );
      expect(fake.capturedSetupCalls, isEmpty);
    });

    test('sendBody fails before connect', () async {
      final fake = ProUsbiNativeBackendFake();
      expect(
        () => fake.sendBody([0x00]),
        throwsA(isA<UsbiTransportException>()),
      );
      expect(fake.capturedBodyCalls, isEmpty);
    });

    test('send calls succeed after connect and capture bytes', () async {
      final fake = ProUsbiNativeBackendFake();
      fake.simulateConnect();
      await fake.sendSetup([0x40, 0xB2, 0x00, 0x00, 0x01, 0x01, 0x06, 0x00]);
      await fake.sendBody([0x00, 0x67, 0x00, 0x80, 0x00, 0x00]);
      expect(fake.capturedSetupCalls.length, 1);
      expect(fake.capturedBodyCalls.length, 1);
      expect(fake.capturedSetupCalls[0][0], 0x40);
      expect(fake.capturedBodyCalls[0][0], 0x00);
      expect(fake.capturedBodyCalls[0][1], 0x67);
    });

    test('readAck returns fakeAckBytes and increments counter', () async {
      final fake = ProUsbiNativeBackendFake();
      fake.simulateConnect();
      final ack = await fake.readAck();
      expect(ack[6], 0x01); // success byte
      expect(fake.ackReadCount, 1);
    });

    test('simulateAccessDenied sets correct status', () {
      final fake = ProUsbiNativeBackendFake();
      fake.simulateAccessDenied();
      expect(fake.status, UsbiBackendStatus.accessDenied);
      expect(fake.isConnected, isFalse);
    });

    test('simulateSetupFailure causes sendSetup to throw', () async {
      final fake = ProUsbiNativeBackendFake(simulateSetupFailure: true);
      fake.simulateConnect();
      expect(
        () => fake.sendSetup([0x40]),
        throwsA(isA<UsbiTransportException>()),
      );
    });

    test('closeDevice resets isConnected', () async {
      final fake = ProUsbiNativeBackendFake();
      fake.simulateConnect();
      await fake.closeDevice();
      expect(fake.isConnected, isFalse);
    });
  });
}
