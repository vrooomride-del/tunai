/// Windows-only USBi native backend via Flutter MethodChannel.
///
/// On non-Windows platforms [checkAvailability] immediately returns
/// [UsbiBackendStatus.unavailable] without touching the channel.
///
/// On Windows, the channel 'tunai/usbi' must be registered by the runner
/// (windows/runner/usbi_channel.cpp). Until the native side is complete,
/// unregistered methods return [UsbiBackendStatus.pending] so the UI can
/// display "Windows native channel pending" without faking success.
///
/// ADI USBi expected VID: 0x0456. PID is not hardcoded — device enumeration
/// returns all matching VID devices; the user selects the target.
library;

import 'dart:io';
import 'package:flutter/services.dart';
import 'pro_usbi_native_backend.dart';

/// Channel name registered by windows/runner/usbi_channel.cpp.
const _kChannel = 'tunai/usbi';

/// Windows-only USBi backend. Delegates all IO to the Win32 runner
/// via [MethodChannel]. Returns [UsbiBackendStatus.unavailable] immediately
/// on non-Windows without calling the channel.
class ProUsbiWindowsNativeBackend implements ProUsbiNativeBackend {
  static const _channel = MethodChannel(_kChannel);

  UsbiBackendStatus _status = UsbiBackendStatus.pending;
  String? _statusDetail;
  bool _isConnected = false;

  @override
  UsbiBackendStatus get status => _status;

  @override
  String? get statusDetail => _statusDetail;

  @override
  bool get isConnected => _isConnected;

  // ── Availability / open / close ───────────────────────────────────────────

  @override
  Future<UsbiBackendStatus> checkAvailability() async {
    if (!Platform.isWindows) {
      _status = UsbiBackendStatus.unavailable;
      _statusDetail = 'Not Windows (${Platform.operatingSystem})';
      return _status;
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('usbi_is_available');
      if (result == null) {
        _status = UsbiBackendStatus.error;
        _statusDetail = 'usbi_is_available returned null';
        return _status;
      }
      final available = result['available'] as bool? ?? false;
      if (available) {
        _status = UsbiBackendStatus.deviceDetected;
        final count = result['device_count'] as int? ?? 0;
        _statusDetail = '$count device(s) found (VID 0x0456)';
      } else {
        _status = UsbiBackendStatus.unavailable;
        _statusDetail = result['detail'] as String? ?? 'No ADI USBi device found';
      }
    } on MissingPluginException {
      // Native channel not yet registered — Windows side implementation pending.
      _status = UsbiBackendStatus.pending;
      _statusDetail = 'Windows native channel not registered — implementation pending';
    } on PlatformException catch (e) {
      _status = UsbiBackendStatus.error;
      _statusDetail = 'usbi_is_available error: ${e.code} — ${e.message}';
    }
    return _status;
  }

  @override
  Future<UsbiBackendStatus> openDevice() async {
    if (!Platform.isWindows) {
      _status = UsbiBackendStatus.unavailable;
      _statusDetail = 'Not Windows';
      return _status;
    }
    if (_status == UsbiBackendStatus.unavailable) return _status;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('usbi_open_device');
      if (result == null) {
        _status = UsbiBackendStatus.error;
        _statusDetail = 'usbi_open_device returned null';
        return _status;
      }
      final success = result['success'] as bool? ?? false;
      final accessDenied = result['access_denied'] as bool? ?? false;
      if (success) {
        _isConnected = true;
        _status = UsbiBackendStatus.connected;
        _statusDetail = null;
      } else if (accessDenied) {
        _isConnected = false;
        _status = UsbiBackendStatus.accessDenied;
        _statusDetail = result['detail'] as String? ?? 'Access denied by OS';
      } else {
        _isConnected = false;
        _status = UsbiBackendStatus.error;
        _statusDetail = result['detail'] as String? ?? 'Failed to open device';
      }
    } on MissingPluginException {
      _status = UsbiBackendStatus.pending;
      _statusDetail = 'Windows native channel not registered — implementation pending';
    } on PlatformException catch (e) {
      if (e.code == 'ACCESS_DENIED') {
        _status = UsbiBackendStatus.accessDenied;
      } else {
        _status = UsbiBackendStatus.error;
      }
      _statusDetail = '${e.code}: ${e.message}';
      _isConnected = false;
    }
    return _status;
  }

  @override
  Future<void> closeDevice() async {
    if (!_isConnected) return;
    try {
      if (Platform.isWindows) {
        await _channel.invokeMethod<void>('usbi_close');
      }
    } on PlatformException catch (e) {
      // Log but do not rethrow — always reset connection state.
      _statusDetail = 'Close error (ignored): ${e.message}';
    } finally {
      _isConnected = false;
      if (_status == UsbiBackendStatus.connected) {
        _status = UsbiBackendStatus.deviceDetected;
      }
    }
  }

  // ── Packet primitives ─────────────────────────────────────────────────────

  @override
  Future<void> sendSetup(List<int> bytes) async {
    _requireConnected('sendSetup');
    try {
      await _channel.invokeMethod<void>('usbi_send_setup', {
        'bytes': Uint8List.fromList(bytes),
      });
    } on PlatformException catch (e) {
      throw UsbiTransportException('sendSetup PlatformException: ${e.code} — ${e.message}');
    }
  }

  @override
  Future<void> sendBody(List<int> bytes) async {
    _requireConnected('sendBody');
    try {
      await _channel.invokeMethod<void>('usbi_send_body', {
        'bytes': Uint8List.fromList(bytes),
      });
    } on PlatformException catch (e) {
      throw UsbiTransportException('sendBody PlatformException: ${e.code} — ${e.message}');
    }
  }

  @override
  Future<List<int>> readAck() async {
    _requireConnected('readAck');
    try {
      final result = await _channel.invokeMethod<Uint8List>('usbi_read_ack');
      if (result == null) throw const UsbiTransportException('readAck returned null');
      return result.toList();
    } on PlatformException catch (e) {
      throw UsbiTransportException('readAck PlatformException: ${e.code} — ${e.message}');
    }
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _requireConnected(String method) {
    if (!_isConnected) {
      throw UsbiTransportException(
          '$method called while not connected — call openDevice() first');
    }
  }
}
