/// Abstract USBi native backend + factory + built-in stubs.
///
/// Production apps use [ProUsbiNativeBackendDisabled] (default on all
/// non-Windows platforms) or [ProUsbiWindowsNativeBackend] on Windows.
/// Tests inject [ProUsbiNativeBackendFake].
library;

import 'dart:io';

// Forward-declare the Windows implementation to allow the factory to
// reference it. The import is safe on all platforms because MethodChannel
// is available everywhere; Platform.isWindows gates actual use.
import 'pro_usbi_windows_native_backend.dart';

/// Describes the readiness of the native USBi backend.
enum UsbiBackendStatus {
  /// Backend is not available on this platform (non-Windows).
  unavailable,

  /// Windows platform confirmed but native channel not yet registered
  /// (Windows native side implementation pending).
  pending,

  /// ADI USBi device detected on USB bus (VID 0x0456).
  deviceDetected,

  /// Driver is loaded and device is accessible (not yet opened).
  driverAvailable,

  /// Device is opened and ready for setup/body/ack calls.
  connected,

  /// Device was found but OS denied access (driver conflict, permissions).
  accessDenied,

  /// Unexpected error — see [statusDetail].
  error,
}

/// Transport contract for USBi hardware access.
/// Implementations: [ProUsbiNativeBackendDisabled], [ProUsbiNativeBackendFake],
/// [ProUsbiWindowsNativeBackend].
abstract class ProUsbiNativeBackend {
  UsbiBackendStatus get status;

  /// Human-readable detail for the current status. Null when status is clear.
  String? get statusDetail;

  bool get isConnected;

  /// Probe the USB bus for ADI USBi devices. Does NOT open the device.
  Future<UsbiBackendStatus> checkAvailability();

  /// Open the detected device for read/write access.
  Future<UsbiBackendStatus> openDevice();

  /// Close the device handle. Safe to call when not connected.
  Future<void> closeDevice();

  // ── Packet primitives — only callable when [isConnected] is true ──────────

  /// Send the USBi setup packet (8 bytes: 40 B2 00 00 01 01 06 00).
  Future<void> sendSetup(List<int> bytes);

  /// Send the USBi body packet (6 bytes: [addr 2B BE] + [data 4B BE]).
  Future<void> sendBody(List<int> bytes);

  /// Send the ACK read request and return the response bytes.
  Future<List<int>> readAck();

  // ── Factory ───────────────────────────────────────────────────────────────

  /// Returns [ProUsbiWindowsNativeBackend] on Windows,
  /// [ProUsbiNativeBackendDisabled] on all other platforms.
  static ProUsbiNativeBackend createDefault() {
    if (Platform.isWindows) return ProUsbiWindowsNativeBackend();
    return ProUsbiNativeBackendDisabled('Windows USBi backend only — not available on ${Platform.operatingSystem}');
  }
}

// ── Disabled stub ─────────────────────────────────────────────────────────────

/// Production stub for non-Windows platforms. All write calls throw.
class ProUsbiNativeBackendDisabled implements ProUsbiNativeBackend {
  final String _reason;
  const ProUsbiNativeBackendDisabled(this._reason);

  @override
  UsbiBackendStatus get status => UsbiBackendStatus.unavailable;

  @override
  String? get statusDetail => _reason;

  @override
  bool get isConnected => false;

  @override
  Future<UsbiBackendStatus> checkAvailability() async => UsbiBackendStatus.unavailable;

  @override
  Future<UsbiBackendStatus> openDevice() async => UsbiBackendStatus.unavailable;

  @override
  Future<void> closeDevice() async {}

  @override
  Future<void> sendSetup(List<int> bytes) =>
      Future.error(UsbiBackendUnavailableException(_reason));

  @override
  Future<void> sendBody(List<int> bytes) =>
      Future.error(UsbiBackendUnavailableException(_reason));

  @override
  Future<List<int>> readAck() =>
      Future.error(UsbiBackendUnavailableException(_reason));
}

// ── Fake for tests ────────────────────────────────────────────────────────────

/// In-process fake backend for unit tests. No OS calls, no MethodChannel.
class ProUsbiNativeBackendFake implements ProUsbiNativeBackend {
  UsbiBackendStatus _status;
  String? _detail;
  bool _connected;

  /// Bytes sent to each method — inspectable by tests.
  final List<List<int>> capturedSetupCalls = [];
  final List<List<int>> capturedBodyCalls = [];
  int ackReadCount = 0;

  /// The ACK bytes [readAck] will return. Defaults to ACK success (byte[6]=0x01).
  List<int> fakeAckBytes;

  /// If true, [sendSetup] throws [UsbiTransportException]. Tests can set this
  /// to simulate a setup failure before body is sent.
  bool simulateSetupFailure;

  /// If true, [sendBody] throws after [sendSetup] succeeds.
  bool simulateBodyFailure;

  ProUsbiNativeBackendFake({
    UsbiBackendStatus initialStatus = UsbiBackendStatus.pending,
    bool connected = false,
    List<int>? fakeAckBytes,
    this.simulateSetupFailure = false,
    this.simulateBodyFailure = false,
  })  : _status = initialStatus,
        _connected = connected,
        fakeAckBytes = fakeAckBytes ??
            [0xC0, 0xB5, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00]; // ACK success

  /// Set status to connected — simulates a successfully opened device.
  void simulateConnect() {
    _connected = true;
    _status = UsbiBackendStatus.connected;
    _detail = null;
  }

  /// Simulate OS denying access to the device.
  void simulateAccessDenied() {
    _connected = false;
    _status = UsbiBackendStatus.accessDenied;
    _detail = 'Simulated access denied';
  }

  /// Simulate device not found.
  void simulateUnavailable() {
    _connected = false;
    _status = UsbiBackendStatus.unavailable;
    _detail = 'No device found (simulated)';
  }

  @override
  UsbiBackendStatus get status => _status;

  @override
  String? get statusDetail => _detail;

  @override
  bool get isConnected => _connected;

  @override
  Future<UsbiBackendStatus> checkAvailability() async {
    if (_status == UsbiBackendStatus.pending) {
      _status = UsbiBackendStatus.deviceDetected;
    }
    return _status;
  }

  @override
  Future<UsbiBackendStatus> openDevice() async {
    if (_status == UsbiBackendStatus.unavailable) return _status;
    simulateConnect();
    return _status;
  }

  @override
  Future<void> closeDevice() async {
    _connected = false;
    if (_status == UsbiBackendStatus.connected) {
      _status = UsbiBackendStatus.deviceDetected;
    }
  }

  @override
  Future<void> sendSetup(List<int> bytes) async {
    _requireConnected('sendSetup');
    if (simulateSetupFailure) throw const UsbiTransportException('Simulated setup failure');
    capturedSetupCalls.add(List.unmodifiable(bytes));
  }

  @override
  Future<void> sendBody(List<int> bytes) async {
    _requireConnected('sendBody');
    if (simulateBodyFailure) throw const UsbiTransportException('Simulated body failure');
    capturedBodyCalls.add(List.unmodifiable(bytes));
  }

  @override
  Future<List<int>> readAck() async {
    _requireConnected('readAck');
    ackReadCount++;
    return List.unmodifiable(fakeAckBytes);
  }

  void _requireConnected(String method) {
    if (!_connected) {
      throw UsbiTransportException('$method called while not connected');
    }
  }
}

// ── Exceptions ────────────────────────────────────────────────────────────────

class UsbiBackendUnavailableException implements Exception {
  final String reason;
  const UsbiBackendUnavailableException(this.reason);
  @override
  String toString() => 'UsbiBackendUnavailableException: $reason';
}

class UsbiTransportException implements Exception {
  final String message;
  const UsbiTransportException(this.message);
  @override
  String toString() => 'UsbiTransportException: $message';
}
