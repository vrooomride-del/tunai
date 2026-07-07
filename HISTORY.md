# TUNAI 개발 히스토리

---

## 2026-06-11

- **커뮤니티 기능** — 게시판, 좋아요, 댓글, 전체 앱 구조 완성
- **소셜 로그인** — 카카오(OAuth2 서버 리다이렉트), 구글, 애플 로그인
- **CI/CD** — GitHub Actions Android APK 자동 빌드
- **T/S 파라미터** — 스피커 프로파일 Fs/Qts/Xmax 입력 → 안전 DSP 자동 적용 (Xmax HPF + 게인 리밋)
- **Android 빌드 수정** — Kotlin 2.1.0, compileSdk 36, Gradle 8.9.1/8.11.1

---

## 2026-06-12

- **기기 QR 등록** — QR 스캔 → 시리얼 번호 조회 및 기기 등록
- **AI 튜닝 패널 (Step 4)** — Gemini AI 공진 분석 → PEQ 파라미터 자동 추천
- **인클로저 탭 제거** — UI 단순화

---

## 2026-06-15

- **멀티 DSP 어댑터 아키텍처** — ADAU1701 / ADAU1466 추상화 레이어 분리
- **칩 명칭 정정** — ADAU1452 → ADAU1466 (CS42448 보드 실제 칩)
- **하드웨어 독립 DSP 레이어 완성** — 보드별 어댑터로 동일 Flutter 코드에서 분기

---

## 2026-06-20

- **AI 백엔드 교체** — Gemini 직접 호출(API 키) → Firebase Functions / Vertex AI 프록시
- **BLE ICP5(WONDOM) 대응** — UUID fff0/fff1/fff2로 업데이트, GATT 덤프 디버그, Android 12+ 권한
- **피크 검출 개선** — CCV 제거, halfWin=30 로컬 최대값 탐색으로 정확도 향상
- **더미 데이터 주입** — 실기기 없이 AI 파이프라인 검증 가능 (디버그 빌드 전용)
- **Firebase Functions 배포** — `aiTune` (모바일 callable) 엔드포인트

---
