import 'audio_analyzer.dart';

/// 읽기 전용 Factory 프리셋 — User 프리셋(My Tune, `my_tune_storage.dart`)과
/// 저장공간/수정권한이 완전히 분리된 별도 계층(AOS 항목 C). `const` 필드만 갖는
/// 불변 클래스라 런타임에 덮어쓰거나 삭제할 수 없고, SharedPreferences 등 어떤
/// 저장소에도 쓰지 않고 코드에 직접 내장돼 있다 — User가 My Tune을 아무리 잘못
/// 저장해도 항상 이 값으로 복귀할 수 있는 "진짜" 안전한 기준점.
///
/// mobile은 Pro와 달리 이름 기반 다중 프리셋 저장 기능이 없어(My Tune은 슬롯 1개뿐,
/// 사용자가 이름을 짓지 않음) "Factory"라는 이름과 충돌할 방법 자체가 없다 — 그래도
/// Factory 콘텐츠 자체는 이 파일에서만 정의되는 단일 소스로 관리한다.
class FactoryPreset {
  final String id;
  final String name;
  final String description;
  final List<ResonancePeak> bands;

  const FactoryPreset({
    required this.id,
    required this.name,
    required this.description,
    required this.bands,
  });
}

/// 실제 공장 캘리브레이션 데이터가 없어(HANDOFF.md 기존 기록 참고) "보정 없는 평탄
/// 기준값"을 Factory로 채택 — PEQ 밴드 0개, 즉 스피커 본연의 응답을 그대로 둔다.
/// 밴드가 비어 있다는 점은 이전(하드코딩된 `const []`)과 같지만, 이제는 이름/설명이
/// 있는 진짜 불변 프리셋 객체로 존재해서 "우연히 안전한 빈 배열"이 아니라 "의도적으로
/// 설계된 기본값"이 됐다.
const kFactoryPresetFlat = FactoryPreset(
  id: 'factory_flat',
  name: 'Factory',
  description: '보정 없는 평탄 기준값 — 언제든 복귀 가능한 안전한 기본 상태',
  bands: [],
);

const kFactoryPresets = <FactoryPreset>[kFactoryPresetFlat];
