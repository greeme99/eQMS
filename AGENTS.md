# eQMS Codex Project Instructions

이 프로젝트는 의료기기·의료장비 제조사를 위한 규제 준수형 eQMS를 개발한다. 이 파일은 Codex 프로젝트 규칙이며, `CLAUDE.md` 또는 `*_CLAUDE.md`가 생기면 해당 파일은 Claude 소유로 간주하고 수정하지 않는다.

## 작업 원칙

- `Understand → Plan → Execute → Verify` 순서를 지킨다.
- `Research/` 원문과 공식 규제·기술 출처를 먼저 확인한다. 출처가 없는 주장은 사실로 확정하지 않는다.
- 요구사항은 `FR-*`, `NFR-*`, `SEC-*`, `DATA-*` ID를 사용하고 URS·위험평가·설계·시험증적·CSV까지 추적한다.
- MVP와 최종 범위를 구분한다. MVP는 문서통제·변경관리·감사추적을 우선하고 CAPA·교육·RTM·RAG·규제 모니터링은 단계적으로 확장한다.
- 규제 적합성을 라이브러리나 코드만으로 주장하지 않는다. 제조사 절차, 권한, 운영 통제, CSV 증적과 함께 검증한다.
- 구현 전 `ponytail`, 완료 전 `ponytail-review`, 두 단계 이상 작업에는 `.Codex/skills/project-workflow`를 적용한다.
- 민감정보·실제 규제 기록·운영 DB를 하네스에 저장하지 않는다. 비밀값은 환경변수로만 주입한다.

## eQMS 기술·검증 경계

- 권장 기준 구조는 FastAPI + PostgreSQL + 원본 보관소(MinIO 또는 승인된 대체) + Keycloak급 IAM + DSS PAdES + Haystack/Qdrant/Ollama 계열 RAG다. 선택은 위험·운영환경 검토 후 확정한다.
- 감사추적은 append-only, 시간·사용자·행위·변경사유·전후값·요청맥락을 기록하고 DB·애플리케이션 이중 통제를 시험한다.
- 전자서명은 서명자·시각·의미·대상 기록 연결과 변조 탐지를 시험한다. DSS가 자동으로 21 CFR Part 11 적합성을 보장한다고 표현하지 않는다.
- RAG는 승인 문서·유효 버전·권한 범위만 검색하고 문서번호·버전·페이지/구간 출처를 제시한다. 근거가 없으면 `Unknown`으로 응답한다.
- 환경은 local → validation/staging → on-prem 운영으로 분리한다. 운영 이관은 변경관리와 CSV 승인 없이는 수행하지 않는다.

## 검증 명령

- 구조·메모리 점검: `pwsh -NoProfile -File ./.Codex/scripts/Test-LearningLoop.ps1`
- 앱 검증 명령은 `plan.md`의 단계별 테스트 표를 기준으로 추가한다.
- macOS에서는 하네스의 Windows 설치기(`install.cmd`, `Install-AllthatCodexHarness.ps1`)를 사용하지 않고 이 프로젝트에 설치된 POSIX 경로 payload를 사용한다.
