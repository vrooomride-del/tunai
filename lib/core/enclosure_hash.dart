import 'dart:convert';
import 'package:crypto/crypto.dart';

/// 인클로저 물리 파라미터
class EnclosureParams {
  final double portDiameterMm;    // 포트 직경 (mm)
  final double portDepthMm;       // 포트 깊이 (mm)
  final double internalVolumeLit; // 내부 용적 (리터)
  final String type;              // 'ported' | 'sealed' | 'passive'
  final String driverSize;        // '4inch' | '5inch' | '6.5inch' 등

  const EnclosureParams({
    required this.portDiameterMm,
    required this.portDepthMm,
    required this.internalVolumeLit,
    required this.type,
    required this.driverSize,
  });

  /// SHA-256 해시 생성 — 동일 인클로저 = 동일 해시
  String get hash {
    // 소수점 1자리로 반올림 (미세 측정 오차 흡수)
    final normalized = {
      'port_d': (portDiameterMm * 10).round() / 10,
      'port_l': (portDepthMm * 10).round() / 10,
      'vol': (internalVolumeLit * 10).round() / 10,
      'type': type,
      'driver': driverSize,
    };
    final jsonStr = jsonEncode(normalized);
    final bytes = utf8.encode(jsonStr);
    return sha256.convert(bytes).toString();
  }

  Map<String, dynamic> toJson() => {
    'port_diameter_mm': portDiameterMm,
    'port_depth_mm': portDepthMm,
    'internal_volume_lit': internalVolumeLit,
    'type': type,
    'driver_size': driverSize,
    'hash': hash,
  };
}
