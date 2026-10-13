# eQMS 종합 개발기획서

문서 상태: 개발 착수용 초안 / 근거 검토 완료 범위와 미확정 사항을 구분함  
작성 기준일: 2026-10-11 KST  
대상: 의료기기·의료장비 제조사의 On-Premise 규제 준수형 eQMS  
하네스: `/Users/greeme/Downloads/AllthatCodexHarness_260729`의 Hermes Growing Agent payload를 프로젝트 내부에 국소 설치

## 1. 결정 요약

이 제품은 문서·품질기록을 통제하고, 변경·승인·전자서명·감사추적·CAPA·교육·설계추적성·검증증적을 하나의 추적 가능한 흐름으로 연결하는 eQMS다. 개발은 다음 순서로 진행한다.

1. Phase 0: 범위·역할·위험·URS·환경분리 확정
2. Phase 1 MVP: 문서통제·버전·승인·변경관리·감사추적
3. Phase 2 통제: 전자서명·RBAC/MFA·원본 무결성·백업/복구
4. Phase 3 품질운영: 부적합·CAPA·교육·내부감사
5. Phase 4 설계·지식: Design and Development File/Medical Device File/Production and Release Records, RTM, 승인문서 RAG
6. Phase 5 운영 자동화: 규제 모니터링·영향평가·재검증·VSR·알림
7. Phase 6 CSV 및 운영전환: VMP/URS/Risk/RTM/IQ/OQ/PQ/VSR 승인 후 On-Prem 이관

MVP와 최종 제품을 혼동하지 않는다. Research 문서 사이의 범위 차이를 반영해 MVP는 작게 고정하되 최종 검증 범위에는 확장 모듈을 포함한다.

## 2. 근거와 신뢰도

### 2.1 읽은 내부 문서

다음 11개 파일을 모두 읽었다. `G-Research.md`는 상용 패키지·국내외 eQMS 개요를, `P-eQMS-01.md`~`P-eQMS-10.md`는 규제 매핑, 아키텍처, SQL/API 예시, CSV 템플릿, 운영 자동화를 다룬다.

| 문서 | 기획 반영 |
|---|---|
| `G-Research.md` | 상용 eQMS·KGMP/FDA/ISO 범위·도입 체크포인트 |
| `P-eQMS-01.md` | 규제 매핑, 오픈소스 스택, RAG/LLM, CSV 로드맵 |
| `P-eQMS-02.md` | Odoo/Nextcloud/FastAPI 역할 분리, MVP와 Part 11 단계 |
| `P-eQMS-03.md` | Sprint 0~4, 감사추적·DSS·RAG PoC, 저장소 구조 |
| `P-eQMS-04.md` | 감사추적 트리거, PAdES, 승인상태, IQ/OQ/PQ, CAPA/교육/RTM |
| `P-eQMS-05.md` | 통합 코드 예시, VMP/URS/Risk/RTM/IQ/OQ/PQ/VSR |
| `P-eQMS-06.md` | CAPA, 교육, RTM 스키마와 미커버 요구사항 리포트 |
| `P-eQMS-07.md` | 통합 시스템 구조와 CSV 수용기준 |
| `P-eQMS-08.md` | 규제 소스 모니터링, IQ/OQ/PQ/VSR, 운영 완료 기준 |
| `P-eQMS-09.md` | 규제 변경 → 영향평가 → CAPA/교육/재검증 흐름 |
| `P-eQMS-10.md` | 영향도 평가, CSV 재검증, VSR 갱신, Slack/메일 알림 |

### 2.2 공식·1차 출처로 확인한 사실

- FDA QMSR는 2026-02-02 시행되었고 21 CFR Part 820에 ISO 13485:2016을 참조로 통합한다. [FDA QMSR](https://www.fda.gov/medical-devices/postmarket-requirements-devices/quality-management-system-regulation-qmsr)
- QMSR 적용 대상은 미국에서 유통되는 finished device 제조사이며, 제조사는 장치별로 적절한 QMS를 수립·유지해야 한다. [eCFR Part 820 §820.1](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-H/part-820)
- 21 CFR Part 11 §11.10은 시스템 검증, 기록 보호·검색, 권한 제한, 독립적인 시간기록 감사추적, 권한 점검을 요구한다. [eCFR Part 11](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11)
- §11.50은 서명자의 인쇄 이름·실행 일시·서명 의미를, §11.70은 서명과 기록의 연결을 요구한다. [eCFR Part 11](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11)
- FDA의 2026 CSA 지침은 생산·QMS 소프트웨어에 대해 의도된 용도와 위험에 비례한 보증·시험 활동을 권고하며, 비구속적 지침임을 명시한다. [FDA CSA Guidance](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/computer-software-assurance-production-and-quality-management-system-software)
- EU EudraLex Volume 4에는 Computerised Systems Annex 11이 공식 목록으로 제공된다. 적용 범위와 최신 개정 여부는 출시 전 QA가 재확인한다. [European Commission EudraLex Volume 4](https://health.ec.europa.eu/medicinal-products/eudralex/eudralex-volume-4_en)

### 2.3 사실·추론·가정·미검증 구분

- **사실:** 위 공식 원문과 내부 Research에 직접 기재된 내용.
- **추론:** 규제 통제를 구현하려면 DB 트리거와 애플리케이션 미들웨어를 함께 시험하는 것이 합리적이라는 설계 판단.
- **가정:** 초기 조직은 50~300명, On-Prem 우선, 실제 운영 DB는 개발환경에 제공되지 않는다.
- **미검증:** ISO 13485 원문 조항, GAMP 5 분류, 국내 KGMP·UDI 세부 매핑, 오픈소스 프로젝트의 현재 유지보수·라이선스·검사기관 수용성, DSS/LLM의 Part 11 적합성.

## 3. 목표·사용자·성공 기준

### 3.1 목표

- 승인된 품질문서와 기록을 단일 이력으로 관리한다.
- 모든 규제 중요 행위가 사용자·시각·변경사유·전후값·증적과 연결된다.
- URS부터 시험·CSV 승인까지 양방향 추적성을 제공한다.
- 승인문서만 권한 필터를 거쳐 검색하고, 답변에 출처·버전을 표시한다.
- Local → validation/staging → On-Prem 운영 이관을 재현 가능한 절차로 만든다.

### 3.2 사용자와 책임

| 역할 | 책임 |
|---|---|
| QA Owner | URS·VMP·위험·검증결과·잔여위험·릴리스 승인 |
| System Owner | 운영환경·계정·백업·복구·변경 승인 |
| IT Validation | IQ/OQ, 환경·설치·백업·복구 증적 |
| Business User | PQ, 실제 SOP/CAPA/교육 업무 검증 |
| Document Owner | 문서 작성·개정·승인요청 |
| Reviewer/Approver | 문서·변경·CAPA 검토 및 승인 |
| Auditor | 감사추적과 검증증적 독립 검토 |
| 교육담당자 | 과정·대상자·이수·인증서 관리 |
| 일반 사용자 | 권한 범위의 승인문서 조회·교육·업무 |

### 3.3 측정 가능한 성공 기준

- High Risk 시험은 100% 통과하거나 승인된 편차가 있어야 한다.
- 모든 URS가 최소 1개 이상의 위험·설계·시험증적에 연결되어야 한다.
- 감사 로그의 변경·삭제 시도는 거부되고, 원 이벤트와 요청 맥락을 조회할 수 있어야 한다.
- 전자서명은 서명자·일시·의미·대상 기록이 표시되고 서명 후 변조가 탐지되어야 한다.
- RAG 회귀셋의 모든 답변은 승인문서·버전·구간 출처를 표시하거나 `Unknown`을 반환해야 한다.
- 백업 후 복구 시험이 성공하고 복구 시점·누락·잔여위험이 기록되어야 한다.

## 4. 범위와 단계

### 4.1 MVP 포함

문서 등록, 메타데이터, 버전 생성, 검토/승인/반려, 유효일·폐기, 배포·회수, 변경요청·영향평가, append-only 감사추적, 기본 RBAC, 요구사항/시험 ID 연결.

### 4.2 MVP 제외 및 후속

CAPA·교육 자동할당·RTM UI·DHF/DMR/MDF 상세, PAdES 운영 연계, RAG·온프레미스 LLM, 규제 모니터링·Slack/메일 알림, ERP/생산설비 연동은 별도 단계로 승인한다.

### 4.3 명칭 정책

기존 Research의 DHF/DMR/DHR 용어와 QMSR 맥락의 Design and Development File, Medical Device File, Production and Release Records를 데이터 모델의 `record_family`와 표시명 매핑으로 함께 보존한다. 규제 문서가 실제 용어 전환을 어떻게 적용하는지는 QA/RA가 확인한다.

## 5. 요구사항(SRS)

### 5.1 기능 요구사항

| ID | 요구사항 | 수용 기준 | 단계 |
|---|---|---|---|
| FR-001 | 문서를 등록하고 소유자·분류·유효일·기밀등급을 지정한다 | 필수 메타데이터 누락을 거부하고 문서 ID를 생성한다 | MVP |
| FR-002 | 문서의 새 버전을 생성하고 이전 버전을 보존한다 | 이전 버전 내용·상태·해시가 변경되지 않는다 | MVP |
| FR-003 | 검토·승인·반려·폐기 상태를 관리한다 | 허용되지 않은 상태 전이를 거부하고 전이를 감사기록한다 | MVP |
| FR-004 | 문서 변경요청과 영향평가를 관리한다 | 영향 범위·승인자·실행 결과가 변경요청에 연결된다 | MVP |
| FR-005 | 규제 중요 행위를 append-only 감사추적한다 | 생성/수정/삭제/승인/조회 이벤트에 사용자·시각·행위·사유·전후값이 있다 | MVP |
| FR-006 | 권한에 따라 조회·작성·검토·승인·서명 기능을 제한한다 | 권한 없는 API와 UI 행동이 모두 거부된다 | MVP/Part11 |
| FR-007 | 전자서명을 기록에 연결한다 | 이름·일시·의미·대상 ID와 변조검증 결과를 표시한다 | Part11 |
| FR-008 | 부적합에서 CAPA 종결까지 추적한다 | NC→원인→조치→효과성→종결 흐름과 담당자를 조회한다 | 확장 |
| FR-009 | 승인 문서 개정 시 교육을 할당한다 | 역할·기한·이수·인증서를 문서 버전에 연결한다 | 확장 |
| FR-010 | URS-설계-시험-증적 RTM을 제공한다 | 미커버 요구사항과 양방향 링크를 보고한다 | 확장 |
| FR-011 | 승인·유효 버전만 RAG 검색한다 | 권한·상태·버전 필터를 통과한 출처만 답변에 사용한다 | 확장 |
| FR-012 | 규제 변경을 감지하고 영향평가·재검증·VSR을 연계한다 | 소스 해시·평가·결론·재검증·알림 이력이 연결된다 | 운영 |

### 5.2 비기능·보안·데이터 요구사항

| ID | 요구사항 | 수용 기준 |
|---|---|---|
| NFR-001 | 환경 분리 | local/validation/production별 DB·계정·스토리지가 분리된다 |
| NFR-002 | 재현성 | 동일 입력으로 설치·마이그레이션·검증 절차를 재실행할 수 있다 |
| NFR-003 | 관찰성 | 요청 ID, 오류, 감사 이벤트 ID, 검증 실행 ID를 상호 연결한다 |
| NFR-004 | 접근성 | 키보드·레이블·포커스·대비·오류 안내를 점검한다 |
| SEC-001 | 최소권한 RBAC/MFA | 역할별 허용·거부 테스트가 통과한다 |
| SEC-002 | 감사추적 무결성 | UPDATE/DELETE 차단, 해시 재계산, 저장소 접근 통제를 검증한다 |
| SEC-003 | 비밀값 보호 | 키·토큰·비밀번호가 저장소·로그·문서에 없다 |
| SEC-004 | RAG 정보 경계 | 권한 없는 문서가 검색·프롬프트·인용에 노출되지 않는다 |
| DATA-001 | 원본 보존 | 원본 파일, 버전, 해시, 보존기간, 폐기 승인 이력이 연결된다 |
| DATA-002 | 시간·식별자 | UTC 저장과 KST 표시 정책, UUID/문서번호, 요청 ID를 일관되게 사용한다 |
| DATA-003 | 백업·복구 | 백업 목록·암호화·복구 지점·복구 시험 증적을 보존한다 |

## 6. 기능 및 상태 규칙

### 6.1 문서 상태

`DRAFT → IN_REVIEW → APPROVED → EFFECTIVE → OBSOLETE`를 기본으로 하며 `IN_REVIEW → REJECTED → DRAFT`, `EFFECTIVE → CHANGE_REQUESTED → 새 DRAFT`를 허용한다. 승인된 버전의 내용과 핵심 메타데이터는 직접 수정하지 않고 새 버전으로 변경한다.

### 6.2 감사 이벤트

DB 트리거는 실제 변경 전후값과 서버 시각을 기록하고, FastAPI 미들웨어는 요청 ID·인증 주체·IP·User-Agent·사유를 보강한다. 운영자/DBA 위협과 저장소 관리자 위협은 WORM 또는 별도 권한·백업 검토로 다룬다. 해시체인은 변조 탐지 통제이지 자동적인 법적 적합성 보증이 아니다.

### 6.3 전자서명

서명 전 재인증과 권한 확인 → 서명 대상 해시 고정 → 이름·시각·의미 기록 → PDF/PAdES 검증 → 서명 후 변조 시험 순서다. DSS는 기술 구성요소이며 Part 11 적합성은 시스템 전체의 검증·절차·교육·운영 통제로 판정한다.

### 6.4 RAG

색인은 `APPROVED`·유효일 내·사용자 권한 허용 문서만 대상으로 한다. 각 chunk에 문서번호·버전·페이지/섹션·해시를 저장한다. 검색 결과가 임계값 미만이면 생성하지 않고 `근거를 찾지 못했습니다`를 반환한다. 모델 성능·라이선스·규제 수용성은 사내 데이터셋으로 별도 평가한다.

## 7. 정보구조와 주요 화면

```text
eQMS
├─ 대시보드 (내 승인·교육·변경·CAPA·검증 경고)
├─ 문서관리
│  ├─ 문서함 / 문서 상세 / 버전 비교 / 승인함 / 배포·회수
├─ 변경관리
│  ├─ 변경요청 / 영향평가 / 승인 / 재검증
├─ 품질운영
│  ├─ 부적합 / CAPA / 교육 / 내부감사
├─ 설계·제품 기록
│  ├─ Design and Development File / MDF / Production & Release / RTM
├─ 지식검색
│  ├─ 승인문서 RAG / 인용 보기 / 답변 피드백
├─ CSV
│  ├─ VMP / URS / Risk / IQ / OQ / PQ / Deviation / VSR
└─ 관리자
   ├─ 사용자·역할 / 감사추적 / 규제 소스 / 알림 / 시스템 설정
```

핵심 경로는 `문서 작성 → 검토 → 승인 → 교육할당 → 유효화 → 변경요청 → 영향평가 → 재검증`이며, 모든 화면은 현재 필터·권한·상태를 유지한다. 표의 정렬은 비활성 `⇅`, 활성 `▲/▼`를 표시하고 오류·빈·권한거부·재시도 상태를 포함한다.

## 8. 기준 아키텍처와 데이터

```text
Browser/SSO
  └─ FastAPI eQMS Core
       ├─ 문서·버전·승인·변경·CAPA·교육·RTM API
       ├─ AuditContext + DB append-only trigger
       ├─ PAdES/DSS adapter
       ├─ RAG API (권한·상태·버전 필터)
       └─ Regulatory monitor / impact / revalidation
          ├─ PostgreSQL Primary/Standby
          ├─ MinIO 또는 승인된 원본 저장소
          ├─ Keycloak급 IAM
          └─ Haystack + Qdrant + Ollama/vLLM (후속)
```

핵심 엔터티: `users`, `roles`, `documents`, `document_versions`, `approval_tasks`, `change_requests`, `audit_events`, `signatures`, `nonconformances`, `capa_records`, `training_assignments`, `requirements`, `risks`, `design_items`, `test_cases`, `evidence`, `regulatory_sources`, `regulatory_updates`, `impact_assessments`, `revalidations`, `vsr_revisions`, `notification_logs`.

외부 컴포넌트는 공식 문서와 라이선스를 확인한 뒤 선택한다: [FastAPI](https://fastapi.tiangolo.com/), [PostgreSQL](https://www.postgresql.org/docs/), [MinIO](https://min.io/docs/minio/linux/index.html), [Keycloak](https://www.keycloak.org/documentation), [EU DSS](https://github.com/esig/dss), [Haystack](https://docs.haystack.deepset.ai/), [Qdrant](https://qdrant.tech/documentation/), [Ollama](https://docs.ollama.com/). 이 링크는 기술 선택의 후보 근거이며 규제 적합성 인증을 의미하지 않는다.

## 9. CSV·검증 전략

### 9.1 산출물

`VMP → URS → Risk Assessment → Functional/Technical Design → RTM → IQ Protocol → OQ Protocol → PQ Protocol → Deviation Log → Test Evidence → VSR → 운영 SOP/교육기록`.

### 9.2 위험 기반 시험

| 위험 | 통제 | 대표 시험 |
|---|---|---|
| 승인 전 문서가 유효화됨 | 상태 전이·권한·유효일 검증 | `TC-FR-003-01` |
| 감사기록 변조/삭제 | DB trigger·권한·해시·백업 | `TC-FR-005-01` |
| 타인 서명/서명 부인 | MFA·재인증·서명 연결 | `TC-FR-007-01` |
| 구버전 검색 노출 | 색인 필터·권한 필터 | `TC-FR-011-01` |
| CAPA 조기 종결 | 효과성 확인 필수 전이 | `TC-FR-008-01` |
| 복구 후 기록 누락 | 백업 복원·대조·재검증 | `TC-DATA-003-01` |
| 규제 변경 누락 | 소스 해시·영향평가·재검증 | `TC-FR-012-01` |

### 9.3 RTM 최소 표

| 요구사항 | 기능 | 화면/API | 구현 위치 | 시험 | CSV 증적 |
|---|---|---|---|---|---|
| FR-001 | F-DOC-01 | 문서 등록 | `app/routers/documents.py` | TC-FR-001-01 | OQ-DOC-001 |
| FR-003 | F-DOC-03 | 승인함 | `app/services/workflow.py` | TC-FR-003-01 | OQ-DOC-003 |
| FR-005 | F-AUD-01 | 감사조회 | `app/core/audit.py`, DB trigger | TC-FR-005-01 | OQ-AT-001/002 |
| FR-007 | F-SIG-01 | 서명 API | `app/services/signature.py` | TC-FR-007-01 | OQ-SIG-001/002 |
| FR-011 | F-RAG-01 | RAG 검색 | `rag/query_pipeline.py` | TC-FR-011-01 | OQ-RAG-001/002 |
| SEC-001 | F-IAM-01 | 역할관리 | `app/security/` | TC-SEC-001-01 | IQ/OQ-SEC-001 |
| DATA-003 | F-OPS-01 | 백업·복구 | `ops/backup/` | TC-DATA-003-01 | PQ-004 |

## 10. 개발 단계·게이트

| 단계 | 기간 제안 | 산출물 | 게이트 |
|---|---:|---|---|
| 0 준비 | 2~4주 | 시스템 인벤토리, 역할, GAMP/CSA 판단, URS 초안 | Gate 1: 범위·위험·데이터·운영환경 승인 |
| 1 MVP | 4~8주 | 문서·버전·승인·변경·감사추적 | Gate 2: 정상/빈/오류/재시도와 인터페이스 결정 |
| 2 통제 | 6~10주 | IAM, PAdES, 원본 저장, 백업/복구 | Gate 3: 권한·서명·무결성 OQ 통과 |
| 3 품질 | 8~12주 | NC/CAPA, 교육, 내부감사 | Gate 4: CAPA 효과성·교육 이력 시험 |
| 4 설계·RAG | 8~12주 | RTM, 설계기록, 승인문서 RAG | Gate 5: 출처·버전·권한 회귀 통과 |
| 5 자동화 | 6~10주 | 규제 모니터·영향평가·재검증·알림 | Gate 6: 영향평가·VSR·재검증 승인 |
| 6 운영전환 | 2~4주 | IQ/OQ/PQ/VSR, SOP, 교육, 릴리스 | Gate 7: QA/System Owner 운영 승인 |

## 11. Codex 하네스 구성

프로젝트 루트에 다음을 설치했다.

- `AGENTS.md`: eQMS 범위·규제·보안·추적성·검증 규칙
- `CODEX.md`: Codex 전용 작업·소유권·전역 설정 보호 규칙
- `DESIGN.md`: 감사 가능한 문서 UI·접근성·상태 표현 규칙
- `.Codex/`: plugin metadata, learning loop, memory, project-workflow, ponytail, 관리 스크립트
- `memory/`: workspace memory와 user preference
- `GROWING-AGENT.md`: 승인형 pending/usage/curator 운영법

하네스 패키지의 Windows 설치기와 전역 `.codex` 교체 절차는 macOS 프로젝트에 적용하지 않았다. 설치 원본은 `/Users/greeme/Downloads/AllthatCodexHarness_260729`이며, 프로젝트 내부 payload만 POSIX 디렉터리로 배치했다. `CLAUDE.md` 계열 파일은 존재하지 않았고 생성·수정하지 않았다.

## 12. 실행 검증 계획

### 현재 수행

- Research 11개 파일 읽기 완료.
- FDA QMSR, eCFR Part 11/820, FDA CSA, EU Annex 11 목록 공식 원문 확인.
- 하네스 payload 파일 설치 및 프로젝트 지침 연결.

### 즉시 실행할 검증

```bash
pwsh -NoProfile -File ./.Codex/scripts/Test-LearningLoop.ps1
find .Codex memory -type f -print | sort
rg -n "CLAUDE|FR-|NFR-|SEC-|DATA-|TC-" AGENTS.md CODEX.md plan.md .Codex/skills/project-workflow/SKILL.md
```

### 개발 시작 후 검증

1. `pytest` 단위시험: 상태 전이, audit append-only, hash chain, RBAC.
2. API 통합시험: 문서 등록→승인→변경→감사조회, 권한 거부, 서명 검증.
3. 데이터시험: 마이그레이션, unique/foreign key/check, 백업/복구.
4. RAG시험: 승인문서·유효버전·권한 필터·출처·Unknown.
5. CSV 시험: IQ/OQ/PQ, 편차·재시험, RTM 미커버 보고, VSR.
6. 목표 On-Prem 환경 E2E: 실제 계정·스토리지·시간동기화·복구.

현재 애플리케이션 코드와 목표 운영 인프라가 아직 없으므로 위 기능·E2E·CSV 시험은 **미실행**이다. 하네스 구조 검증과 문서 근거 확인을 애플리케이션 검증으로 오인하지 않는다.

## 13. 미확정·승인 필요 사항

- 제조국·판매국·제품 분류와 KGMP/UDI/ISO/IEC 적용 범위
- 실제 사용자 수, 보존기간, RTO/RPO, 네트워크·인증 인프라
- GAMP Category 4/5 또는 CSA 위험 분류
- PostgreSQL HA, MinIO WORM, Keycloak, DSS 운영 책임과 키 관리
- 오픈소스 라이선스·지원·검사기관 수용성
- RAG 모델·임베딩·평가셋·금지 데이터 정책
- Slack/메일 외부 반출 승인과 규제 알림 주기
- QA/RA가 승인할 VMP·URS·수용기준·편차처리 절차

이 항목은 구현자가 임의로 확정하지 않고 Gate 1에서 결정한다.

## 14. 내부 근거 위치

세부 코드 예시와 템플릿은 `Research/P-eQMS-01.md`~`P-eQMS-10.md`의 해당 장을 원문으로 확인한다. 특히 감사추적·전자서명은 P-eQMS-03~05, CAPA·교육·RTM은 P-eQMS-06~07, 규제 모니터링·재검증은 P-eQMS-08~10을 근거로 한다. 내부 문서의 블로그·상용 사이트 인용은 공식 원문 확인 전 참고자료로만 취급한다.
