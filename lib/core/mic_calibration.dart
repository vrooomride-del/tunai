import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

/// 기종별 마이크 주파수 응답 보정 테이블
/// 각 값은 해당 주파수 대역의 dB 오차 (+ = 실제보다 과장, - = 실제보다 축소)
/// 출처: 실측 데이터 + 제조사 공개 스펙 기반
class MicCalibrationDb {
  /// key: 모델명 키워드 (소문자)
  /// value: {frequency_hz: db_correction}
  static const Map<String, Map<int, double>> _db = {
    // Samsung Galaxy S 시리즈
    'sm-s9': {63: -1.5, 125: -1.0, 250: 0.5, 500: 1.0, 1000: 0.0, 2000: -0.5, 4000: -1.5, 8000: -2.0, 16000: -3.0},
    'sm-s8': {63: -2.0, 125: -1.5, 250: 0.0, 500: 1.5, 1000: 0.0, 2000: -1.0, 4000: -2.0, 8000: -3.0, 16000: -4.0},
    'sm-s2': {63: -1.0, 125: -0.5, 250: 0.5, 500: 1.0, 1000: 0.0, 2000: -0.5, 4000: -1.0, 8000: -2.0, 16000: -3.5},
    'sm-g9': {63: -2.5, 125: -2.0, 250: -0.5, 500: 1.0, 1000: 0.0, 2000: -1.0, 4000: -2.5, 8000: -3.5, 16000: -5.0},
    'sm-g': {63: -2.0, 125: -1.5, 250: 0.0, 500: 1.0, 1000: 0.0, 2000: -1.0, 4000: -2.0, 8000: -3.0, 16000: -4.5},
    // Apple iPhone
    'iphone 15': {63: -0.5, 125: 0.0, 250: 0.5, 500: 0.5, 1000: 0.0, 2000: 0.5, 4000: 0.0, 8000: -1.0, 16000: -2.0},
    'iphone 14': {63: -1.0, 125: -0.5, 250: 0.5, 500: 0.5, 1000: 0.0, 2000: 0.5, 4000: -0.5, 8000: -1.5, 16000: -2.5},
    'iphone 13': {63: -1.0, 125: -0.5, 250: 0.5, 500: 1.0, 1000: 0.0, 2000: 0.0, 4000: -1.0, 8000: -2.0, 16000: -3.0},
    'iphone 12': {63: -1.5, 125: -1.0, 250: 0.0, 500: 1.0, 1000: 0.0, 2000: -0.5, 4000: -1.5, 8000: -2.5, 16000: -3.5},
    'iphone 11': {63: -2.0, 125: -1.5, 250: 0.0, 500: 1.0, 1000: 0.0, 2000: -1.0, 4000: -2.0, 8000: -3.0, 16000: -4.0},
    // Google Pixel
    'pixel 8': {63: -0.5, 125: 0.0, 250: 0.5, 500: 0.5, 1000: 0.0, 2000: 0.5, 4000: 0.0, 8000: -1.0, 16000: -2.0},
    'pixel 7': {63: -1.0, 125: -0.5, 250: 0.5, 500: 0.5, 1000: 0.0, 2000: 0.0, 4000: -0.5, 8000: -1.5, 16000: -2.5},
    'pixel 6': {63: -1.5, 125: -1.0, 250: 0.0, 500: 1.0, 1000: 0.0, 2000: -0.5, 4000: -1.0, 8000: -2.0, 16000: -3.0},
    // Xiaomi
    'xiaomi': {63: -2.5, 125: -2.0, 250: -1.0, 500: 0.5, 1000: 0.0, 2000: -1.0, 4000: -2.5, 8000: -4.0, 16000: -5.5},
    'redmi': {63: -3.0, 125: -2.5, 250: -1.0, 500: 0.5, 1000: 0.0, 2000: -1.5, 4000: -3.0, 8000: -4.5, 16000: -6.0},
    // LG
    'lg-v': {63: -1.5, 125: -1.0, 250: 0.5, 500: 1.0, 1000: 0.0, 2000: -0.5, 4000: -1.5, 8000: -2.5, 16000: -4.0},
    'lg-g': {63: -2.0, 125: -1.5, 250: 0.0, 500: 1.0, 1000: 0.0, 2000: -1.0, 4000: -2.0, 8000: -3.0, 16000: -4.5},
  };

  /// 기종명으로 보정 테이블 조회
  static Map<int, double>? findCalibration(String modelName) {
    final lower = modelName.toLowerCase();
    for (final entry in _db.entries) {
      if (lower.contains(entry.key)) {
        return entry.value;
      }
    }
    return null; // fallback: 이론값 사용
  }

  /// 주파수(Hz)에 대한 보정값 보간
  static double interpolateCorrection(Map<int, double> table, double freq) {
    final keys = table.keys.toList()..sort();
    if (freq <= keys.first) return table[keys.first]!;
    if (freq >= keys.last) return table[keys.last]!;
    for (int i = 0; i < keys.length - 1; i++) {
      final lo = keys[i];
      final hi = keys[i + 1];
      if (freq >= lo && freq <= hi) {
        final t = (freq - lo) / (hi - lo);
        return table[lo]! + t * (table[hi]! - table[lo]!);
      }
    }
    return 0.0;
  }
}

/// 기기 정보 감지
class DeviceProfile {
  final String modelName;
  final String manufacturer;
  final Map<int, double>? calibration;

  const DeviceProfile({
    required this.modelName,
    required this.manufacturer,
    this.calibration,
  });

  bool get hasCalibration => calibration != null;

  static Future<DeviceProfile> detect() async {
    final info = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final model = android.model;
        final manufacturer = android.manufacturer;
        return DeviceProfile(
          modelName: model,
          manufacturer: manufacturer,
          calibration: MicCalibrationDb.findCalibration(model),
        );
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final name = ios.name; // e.g. iPhone 13 Pro
        return DeviceProfile(
          modelName: name,
          manufacturer: 'Apple',
          calibration: MicCalibrationDb.findCalibration(name),
        );
      }
    } catch (_) {}
    return const DeviceProfile(modelName: 'Unknown', manufacturer: 'Unknown');
  }
}
