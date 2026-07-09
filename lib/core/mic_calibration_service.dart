import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'mic_calibration.dart';
import 'mic_calibration_profile.dart';

/// Returns a consumer-facing [MicCalibrationProfile] for the current device.
/// Internally uses [DeviceProfile] + [MicCalibrationDb], but only exposes
/// consumer-safe language to the UI layer.
class MicCalibrationService {
  MicCalibrationService._();

  static const _knownProfiles = <String, (String, String)>{
    // modelKeyword (lowercase) → (profileName, confidence)
    'iphone 15': ('iPhone 15', 'High'),
    'iphone 14': ('iPhone 14', 'High'),
    'iphone 13': ('iPhone 13', 'High'),
    'iphone 12': ('iPhone 12', 'High'),
    'iphone 11': ('iPhone 11', 'Medium'),
    'sm-s24': ('Galaxy S24', 'High'),
    'sm-s23': ('Galaxy S23', 'High'),
    'sm-s22': ('Galaxy S22', 'High'),
    'sm-s21': ('Galaxy S21', 'Medium'),
    'pixel 8': ('Pixel 8', 'High'),
    'pixel 7': ('Pixel 7', 'High'),
    'pixel 6': ('Pixel 6', 'Medium'),
  };

  static Future<MicCalibrationProfile> detect() async {
    final device = await DeviceProfile.detect();
    final os = Platform.isIOS ? 'iOS' : Platform.isAndroid ? 'Android' : 'Unknown';
    final lower = device.modelName.toLowerCase();

    for (final entry in _knownProfiles.entries) {
      if (lower.contains(entry.key)) {
        final (name, confidence) = entry.value;
        return MicCalibrationProfile(
          deviceModel: device.modelName,
          os: os,
          profileName: name,
          confidence: confidence,
          correctionVersion: 'v1.0',
          isGeneric: false,
        );
      }
    }

    return MicCalibrationProfile(
      deviceModel: device.modelName.isEmpty ? 'Unknown' : device.modelName,
      os: os,
      profileName: 'Generic Phone Mic',
      confidence: 'Medium',
      correctionVersion: 'v1.0-generic',
      isGeneric: true,
    );
  }
}

// Riverpod provider — loaded once per app session.
final micCalibrationProfileProvider =
    FutureProvider<MicCalibrationProfile>((ref) => MicCalibrationService.detect());
