# TUNAI 인계 노트

> 작성일: 2026-06-20

---

## 이번 세션에서 완료한 것

### 모바일 (tunai/)
| 항목 | 커밋 | 내용 |
|---|---|---|
| AI APPLY 버튼 | `c368c60` | 밴드별 APPLY + APPLY ALL → BLE 즉시 전송. 연결 안 된 상태 안내 |
| SafetyProfile HPF 연결 | `c368c60` | speakerProfileProvider 추가, 측정 시 clampBassBoost 실제 동작, APPLY DSP 시 HPF(0x000B) prepend |
| lint 수정 | `1d95aff` | curly_braces_in_flow_control |

### Pro (tunai_pro/)
| 항목 | 커밋 | 내용 |
|---|---|---|
| FRD 그래프 | `f232ed5` | DRIVERS 탭 FRD 임포트 후 로그 주파수 축 Bode 그래프 표시 |
| AI 컨텍스트 보강 | `f232ed5` | AI 호출 시 systemProfile 전달 (채널 구성/보드 정보) |

---

## 다음 세션 대기 중인 결정사항

**3-3 APPLY 자동 전송 (Pro)**
- 제안: 자동 전송 안 함 (현 구조 유지)
- 이유: APPLY ALL → 즉시 전송이면 실수 위험. 대신 isDirty=true 시 SEND TO DSP 버튼 자동 강조 (이미 동작)
- 사용자 확인 필요 — 이번 세션에서 구현하지 않음

---

## 남은 우선순위 (다음 세션)

| 순위 | 레포 | 작업 |
|---|---|---|
| P1 | Pro+모바일 | **ADAU1466 SigmaStudio 주소맵 확정** → 파란보드 DSP 전송 활성화 (하드웨어 도착 후) |
| P2 | 모바일 | **AI에 scmsBins 전체 스펙트럼 전달** — 현재 peaks 목록만 전달, scmsBins 미전달 |
| P3 | 모바일 | **커뮤니티 프리셋 업로드 시 peaks 데이터 첨부** (`fps: []` 빈 배열 → 실제 데이터) |
| P4 | Pro | **ADAU1701 Gain/Delay PRAM 주소 확정** (`_gainBase=0x0000` TODO) |
| P5 | Pro | **유료 프리셋 판매 UI** (API는 준비됨, 가격 설정 화면 없음) |

---

## 알려진 제약

- `DspCompiler.hpfPramAddr = 0x000B` — TUNAI 펌웨어 SigmaStudio 레이아웃 기준 추정값.
  실기기 연결 후 HPF가 올바른 위치에 적용되는지 테스트 필요. 틀리면 상수 수정.
- ADAU1466 어댑터 5개 메서드 전부 `UnimplementedError` — 보드 도착 후 별도 세션.
