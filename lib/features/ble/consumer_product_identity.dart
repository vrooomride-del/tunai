import 'package:flutter/foundation.dart';

/// Consumer-safe identity derived from physical advertising data and the
/// existing supported-profile handshake. Raw module names stay inside BLE.
@immutable
class ConsumerProductIdentity {
  static const tunaiOneDisplayName = 'TUNAI ONE';
  static const nearbySpeakerDisplayName = 'Nearby speaker';

  final String displayName;
  final bool isConfirmed;
  final bool isHighConfidenceCandidate;

  const ConsumerProductIdentity._({
    required this.displayName,
    required this.isConfirmed,
    required this.isHighConfidenceCandidate,
  });

  factory ConsumerProductIdentity.fromPhysicalIdentity({
    required String physicalDeviceName,
    required bool supportedProfileValidated,
  }) {
    if (supportedProfileValidated) {
      return const ConsumerProductIdentity._(
        displayName: tunaiOneDisplayName,
        isConfirmed: true,
        isHighConfidenceCandidate: true,
      );
    }
    final normalized = physicalDeviceName.trim().toUpperCase();
    final candidate = normalized == 'WONDOM ICP5' ||
        normalized == 'CH9143BLE2U' ||
        normalized == 'ICP5';
    return ConsumerProductIdentity._(
      displayName: candidate
          ? tunaiOneDisplayName
          : nearbySpeakerDisplayName,
      isConfirmed: false,
      isHighConfidenceCandidate: candidate,
    );
  }

  static String signalQuality(int? rssi, {required bool ko}) {
    if (rssi == null) return ko ? '신호 확인 중' : 'Signal unavailable';
    if (rssi >= -60) return ko ? '신호 강함' : 'Strong signal';
    if (rssi >= -75) return ko ? '신호 양호' : 'Good signal';
    return ko ? '신호 약함' : 'Weak signal';
  }
}
