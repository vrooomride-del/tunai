import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'profiles/system_profile.dart';

/// 선택된 스피커 T/S 프로파일 전역 상태 (core에 선언 — circular import 방지)
final speakerProfileProvider = StateProvider<SpeakerProfile?>((ref) {
  final sys = ref.watch(systemProfileProvider);
  return sys.id == SystemProfileId.tunaiOne ? kTunaiOneProfile : null;
});

class SpeakerProfile {
  final String id;
  final String name;
  final String description;
  final double fs;
  final double qts;
  final double vas;
  final double xmax;
  final double sensitivity;
  final double? enclosureVolume;
  final double? portLength;
  final double? portDiameter;

  const SpeakerProfile({
    required this.id, required this.name, required this.description,
    required this.fs, required this.qts, required this.vas,
    required this.xmax, required this.sensitivity,
    this.enclosureVolume, this.portLength, this.portDiameter,
  });

  double get recommendedHpfFreq => fs * 0.85;

  /// T/S 기반 크로스오버 주파수 추정 (멀티웨이 전용)
  /// Qts < 0.4: 밀폐 특성 → Fs × 20 (중고역 크로스오버 유리)
  /// Qts 0.4~0.7: 표준 → Fs × 28 (일반적 2웨이 크로스오버)
  /// Qts > 0.7: 고Qts → Fs × 35 (저역 연장 제한, 낮은 크로스 불가)
  double get recommendedCrossoverFreq {
    if (qts < 0.4) return (fs * 20).clamp(800, 4000);
    if (qts < 0.7) return (fs * 28).clamp(1000, 5000);
    return (fs * 35).clamp(1500, 6000);
  }
  double get maxBassBoostDb {
    if (xmax >= 10) return 6.0;
    if (xmax >= 6) return 4.0;
    if (xmax >= 3) return 2.0;
    return 0.0;
  }
  double get gainReferenceOffset => sensitivity - 85.0;

  Map<String, dynamic> toPromptMap() => {
    'name': name, 'fs_hz': fs, 'qts': qts, 'vas_liters': vas,
    'xmax_mm': xmax, 'sensitivity_db': sensitivity,
    if (enclosureVolume != null) 'enclosure_volume_liters': enclosureVolume,
    if (portLength != null) 'port_length_mm': portLength,
    if (portDiameter != null) 'port_diameter_mm': portDiameter,
    'derived': {
      'recommended_hpf_hz': recommendedHpfFreq,
      'max_bass_boost_db': maxBassBoostDb,
      'gain_reference_offset_db': gainReferenceOffset,
    },
  };
}

const kTunaiOneProfile = SpeakerProfile(
  id: 'tunai_one', name: 'TUNAI One',
  description: 'TUNAI One 기본 스피커 (4" 풀레인지)',
  fs: 75.0, qts: 0.38, vas: 3.2, xmax: 4.5, sensitivity: 87.0,
  enclosureVolume: 4.0, portLength: 65.0, portDiameter: 50.0,
);

const kBuiltinProfiles = [kTunaiOneProfile];

enum SpeakerProfileMode { builtin, custom, skip }

class SpeakerProfileState {
  final SpeakerProfileMode mode;
  final SpeakerProfile? selectedProfile;
  final SpeakerProfile? customProfile;

  const SpeakerProfileState({
    this.mode = SpeakerProfileMode.skip,
    this.selectedProfile, this.customProfile,
  });

  SpeakerProfile? get activeProfile {
    if (mode == SpeakerProfileMode.builtin) return selectedProfile;
    if (mode == SpeakerProfileMode.custom) return customProfile;
    return null;
  }

  SpeakerProfileState copyWith({
    SpeakerProfileMode? mode,
    SpeakerProfile? selectedProfile,
    SpeakerProfile? customProfile,
  }) => SpeakerProfileState(
    mode: mode ?? this.mode,
    selectedProfile: selectedProfile ?? this.selectedProfile,
    customProfile: customProfile ?? this.customProfile,
  );
}
