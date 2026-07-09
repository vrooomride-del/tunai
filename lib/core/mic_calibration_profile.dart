/// Consumer-facing mic calibration profile.
/// Wraps DeviceProfile into language suitable for the Consumer UI.
/// No technical frequency correction terms are exposed here.
class MicCalibrationProfile {
  final String deviceModel;
  final String os;
  final String profileName;

  /// Consumer-visible confidence label.
  /// 'High' / 'Medium' / 'Low' — never exposes dB values or correction curves.
  final String confidence;

  /// Internal version tag for future update matching.
  final String correctionVersion;

  /// True when no device-specific profile was found.
  final bool isGeneric;

  /// Optional internal notes (not shown in Consumer UI).
  final String? notes;

  const MicCalibrationProfile({
    required this.deviceModel,
    required this.os,
    required this.profileName,
    required this.confidence,
    required this.correctionVersion,
    required this.isGeneric,
    this.notes,
  });

  static const MicCalibrationProfile generic = MicCalibrationProfile(
    deviceModel: 'Unknown',
    os: 'Unknown',
    profileName: 'Generic Phone Mic',
    confidence: 'Medium',
    correctionVersion: 'v1.0-generic',
    isGeneric: true,
    notes: 'No device-specific profile found. Generic profile applied.',
  );

  /// Consumer UI status string.
  String statusLabel({bool ko = false}) {
    if (isGeneric) {
      return ko
          ? '기본 휴대폰 마이크 프로파일이 적용되었습니다.'
          : 'Generic phone microphone profile applied.';
    }
    return ko
        ? '휴대폰 마이크 준비 완료'
        : 'Phone microphone ready.';
  }

  /// Consumer UI confidence label.
  String confidenceLabel({bool ko = false}) {
    final label = switch (confidence) {
      'High' => ko ? '높음' : 'High',
      'Medium' => ko ? '보통' : 'Medium',
      _ => ko ? '낮음' : 'Low',
    };
    return ko ? '측정 신뢰도: $label' : 'Measurement confidence: $label';
  }
}
