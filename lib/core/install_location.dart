import 'package:flutter_riverpod/flutter_riverpod.dart';

enum InstallLocation { desk, livingRoom, nearWall, studio, custom }

extension InstallLocationLabel on InstallLocation {
  String get label => switch (this) {
        InstallLocation.desk => '책상 (Desk)',
        InstallLocation.livingRoom => '거실 (Living Room)',
        InstallLocation.nearWall => '벽 근처 (Near Wall)',
        InstallLocation.studio => '스튜디오 (Studio)',
        InstallLocation.custom => '직접 입력 (Custom)',
      };

  /// AI 프롬프트에 포함할 영문 위치 키
  String get promptKey => switch (this) {
        InstallLocation.desk => 'desk',
        InstallLocation.livingRoom => 'living_room',
        InstallLocation.nearWall => 'near_wall',
        InstallLocation.studio => 'studio',
        InstallLocation.custom => 'custom',
      };
}

/// MEASURE 탭에서 선택한 설치 위치 — AI 분석 프롬프트에 자동 포함됨
final installLocationProvider = StateProvider<InstallLocation?>((ref) => null);

/// "직접 입력" 선택 시 사용자가 적은 자유 텍스트
final installLocationCustomTextProvider = StateProvider<String>((ref) => '');
