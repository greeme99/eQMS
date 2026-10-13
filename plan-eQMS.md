# 의료기기 품질·GMP 관리 시스템(Medical eQMS) 구축 종합계획서

| 항목 | 내용 |
|---|---|
| 문서번호 | PLAN-EQMS-001 |
| 버전 | 1.0 |
| 작성일 | 2026-10-11 |
| 대상 시스템 | Medical eQMS (의료기기 품질·GMP 통합관리 시스템) |
| 배포 형태 | On-Premise (사내 AX 서버) |
| GAMP 5 분류 | Category 4(설정형) + Category 5(커스텀 모듈) 혼합 |
| 근거 문서 | G-Research.md, P-eQMS-01 ~ P-eQMS-10 |
| 작성 원칙 | 제공 문서에 근거한 내용만 기술. 미확인 항목은 §13에 별도 표기 |

> **약어**: eQMS(Electronic Quality Management System, 전자품질경영시스템) / GMP(Good Manufacturing Practice) / CSV(Computer System Validation, 컴퓨터 시스템 밸리데이션) / CSA(Computer Software Assurance) / QMSR(Quality Management System Regulation) / URS(User Requirements Specification) / RTM(Requirements Traceability Matrix) / VMP(Validation Master Plan) / VSR(Validation Summary Report) / IQ·OQ·PQ(Installation·Operational·Performance Qualification) / CAPA(Corrective And Preventive Action) / NC(Nonconformance) / MDF(Medical Device File) / DHF·DMR·DHR(Design History File·Device Master Record·Device History Record) / PAdES(PDF Advanced Electronic Signatures) / DSS(Digital Signature Service) / RAG(Retrieval-Augmented Generation) / WORM(Write Once Read Many) / RBAC(Role-Based Access Control) / SaMD(Software as a Medical Device) / UDI(Unique Device Identification)

---

## Executive Summary

최소 투자로 규제 준수형 eQMS를 확보하는 가장 현실적인 경로는 **"오픈소스 운영기반(Odoo·Nextcloud) + 자체 개발 규제통제 계층(FastAPI·PostgreSQL)"의 이원 구조**이며, 4주 MVP(감사추적·문서버전·전자서명·RAG)를 먼저 확보한 뒤 CAPA·교육·설계추적성·CSV 패키지를 순차 확장한다. 핵심 설계 원칙은 **규제 기록은 append-only로 보존**, **문서 원본은 무결성 저장소(WORM)에 보관**, **모든 승인·서명·검색 행위는 감사추적과 연결**이며, 규제 준수의 책임은 제품이 아니라 제조사에게 있으므로 CSV 문서 패키지를 개발과 **병행** 축적한다.

**총 구축 기간**: 약 12개월 (MVP 4주 + 확장 6단계)
**핵심 리스크**: 오픈소스 eQMS의 감사기관 수용 여부, 21 CFR Part 11 불변성 구현 난이도, LLM 환각 → 각각 CSV 증적·WORM·출처인용 강제로 완화

---

## 1. 목표 및 범위

### 1.1 구축 목표

| # | 목표 | 완료 기준 |
|---|---|---|
| 1 | 규제 준수형 프로세스·워크플로 운영 Backend 구축 | 문서 등록→검토→승인→배포→회수 전 과정 전산화 |
| 2 | 전자서명 연동 및 데이터 위·변조 방지 감사추적 구현 | FDA 21 CFR Part 11 요구 충족, UPDATE/DELETE 차단 |
| 3 | 문서·기록관리용 이중화 DB 및 무결성 Storage 구성 | PostgreSQL Primary/Standby, MinIO WORM |
| 4 | GMP 가이드라인·제품표준서(DMR/DHR/DHF)의 이력 버전관리 체계 | 구버전 SUPERSEDED, 전 버전 이력 보존 |
| 5 | 보안형 RAG 기반 품질정보(SOP·규제규격) 조회 | 승인 문서만 검색, 출처·버전 100% 인용 |
| 6 | 사내 문서 유출 방지 On-Premise LLM 품질 AI 비서 | 외부 API 미사용, 온프레미스 추론 |
| 7 | 개발/운영 환경 분리 및 CSV 수행 후 운영 전환 | IQ/OQ/PQ 완료, VSR 승인 |

### 1.2 범위

**포함(In Scope)**
- 문서등록 및 버전관리 / 승인 워크플로 / 감사추적 / PAdES 전자서명
- CAPA(NC→CAPA→효과성 확인) / 교육·이수관리 / 설계추적성(RTM)
- Design and Development File, Medical Device File(MDF)
- 승인 SOP RAG 검색 / 규제 변경 모니터링 및 자동 영향도 평가

**제외(Out of Scope)**
- ERP 재무연동 / 외부 협력사 포털 / 생산설비 제어 시스템 / 경영 BI

### 1.3 전제 조건

- 사내 AX 서버 온프레미스 운영, 소규모~중견 규모(50~300명)
- 초기 투자 최소화 우선 (바이브코딩 기반 자체 개발)
- 개발(Local PC) / 검증(Staging) / 운영(사내 AX 서버) 3환경 분리

---

## 2. 규제 요구사항 매핑

### 2.1 적용 규제

| 규제 | 핵심 요구사항 | 시스템 기능 매핑 |
|---|---|---|
| **ISO 13485:2016** | 문서관리(4.2), 설계관리(7.3), CAPA(8.5), 기록관리(4.2.5) | DMS, DHF/MDF, CAPA, Audit Trail |
| **FDA QMSR (21 CFR 820)** | 설계관리(820.30), CAPA(820.100), 생산관리(820.70), 기록(820.180) | Design Controls, NC, 생산·출하기록, 추적성 |
| **21 CFR Part 11** | 전자서명(11.50, 11.70), 감사추적(11.10(e)), 접근제어(11.10(d)) | 전자서명 모듈, Time-stamped Audit Log, RBAC |
| **EU Annex 11** | 컴퓨터화 시스템 통제 | CSV 패키지, 변경통제 |
| **GAMP 5** | 위험 기반 검증, RTM, IQ/OQ/PQ, VSR | CSV 패키지 전반 |
| **식약처 KGMP / UDI** | 품목허가, 공급내역 보고 | (Phase 5 이후 연계 검토 — §13 참조) |

### 2.2 용어 전환 (FDA QMSR)

FDA QMSR은 2026년 2월 2일부터 시행되었으며 ISO 13485:2016을 참조한다. 기존 명칭은 사라졌으나 **기록 요구 자체는 유지**되므로, 기존 문서 색인과 신규 색인을 병행하는 **이중 매핑표**를 운영한다.

| 기존 용어 | QMSR / ISO 13485 관점 | 시스템 모듈 |
|---|---|---|
| DHF | Design and Development File (ISO 13485 Cl. 7.3.10) | 설계개발 파일 |
| DMR | Medical Device File (MDF, Cl. 4.2.3) | 제품기준·제조기준 파일 |
| DHR | Production and Release Records | 생산·출하 기록 |

### 2.3 Part 11 필수 구현 항목

**감사추적(Audit Trail)**
- 생성/수정/삭제의 날짜·시간 (컴퓨터 생성, 시간 기록)
- 변경자 ID / 변경 사유
- 이전 기록 가독성 유지 (덮어쓰기 금지)

**전자서명(Electronic Signature)**
- 서명자 인쇄된 이름
- 서명 실행 날짜·시간
- 서명 의미 (검토 REVIEW / 승인 APPROVAL / 책임 RESPONSIBILITY)
- 전자기록과 영구 연결, 서명 후 원문 변경 탐지 가능

---

## 3. 현재 상태 진단 및 Build vs Buy 판단

### 3.1 상용 솔루션 벤치마킹 (G-Research 기준)

| 구분 | 솔루션 | 타겟·특징 |
|---|---|---|
| **글로벌 eQMS** | Greenlight Guru | MedTech 스타트업·중소기업, 설계통제(Design Control) 강화 |
| | MasterControl | 글로벌 대기업·중견, ERP/MES 연동 유연성 |
| | Qualio | 성장기 기업, 템플릿 기반 빠른 도입, SQM |
| | SimplerQMS | Life Science 전용 사전 밸리데이션, MS 100% 호환 |
| **국내 KGMP·UDI** | GMS-MD (에스지아이시스템) | 의료기기 ERP + GMP 결합, 식약처 통합정보시스템 UDI 직접 연동 |
| | ICUBE G2 / 더존 ERP 확장 | 표준 ERP + Lot 추적 + KGMP 기록물 애드온 |
| | 코아시아·영림원 MES | 설비 인터페이스 연동, eDHR 자동 생성 |
| **SaMD 특화** | Ketryx | Jira/GitHub 연동, IEC 62304, SBOM·사이버보안 문서 자동 생성 |
| | Matrix Req | 요구사항→V&V 계층·변경 추적 경량 ALM/QMS |

### 3.2 오픈소스 대안

| 프로젝트 | 라이선스 | 스택 | 21 CFR Part 11 |
|---|---|---|---|
| QAtrial | AGPL-3.0 | React + Prisma + PostgreSQL | 전자서명·감사로그 포함 |
| OpenQMS | - | Cloud-Native | 명시적 지원 |
| dearauditor-qms-baseline | MIT | Git-native (Issues/PR/Actions) | GAMP 5 / Part 11 오버레이 |
| GSTT-CSC QMS Template | - | Git 기반 템플릿 | ISO 13485 SaMD SOP·CAPA·위험등록부 |

### 3.3 판단: 하이브리드 자체 구축

| 평가 항목 | Odoo | Nextcloud | FastAPI + PostgreSQL 커스텀 |
|---|---|---|---|
| 주 역할 | ERP·BOM·구매·재고·생산출하 기록 | 문서 저장·공유·협업·버전관리 | **규제 핵심 워크플로·감사추적·전자서명** |
| 문서관리 | 문서 모듈·첨부 | 강점: Files, 버전관리, 공유 | 메타데이터·승인·버전 정책 |
| 품질 워크플로 | CAPA/NC/변경관리 커스텀 필요 | QMS 특화 아님 | URS 기반 맞춤 설계 |
| 감사추적 | 기본 제공으로 Part 11 보장 불가 | 규제 기록 수준 별도 검증 필요 | append-only 직접 구현 |
| 전자서명 | 커스텀 필요 | 외부 연동 필요 | DSS PAdES 연동 |
| RAG·LLM | 별도 구축 | 별도 구축 | Haystack + Qdrant 직접 통합 |

> **중요**: Odoo·Nextcloud는 그 자체로 "Part 11 인증 제품"이 아니다. 전자서명·감사추적·변경관리는 **제조사가 구현·검증·문서화**해야 한다.

### 3.4 패키지 도입 시 체크포인트 (대안 평가용)

1. **소프트웨어 밸리데이션(CSV) 제공 여부** — IQ/OQ/PQ 문서 패키지 기본 제공 확인
2. **21 CFR Part 11 준수** — 전자서명·감사추적 봉인, 위·변조 불가 구조

---

## 4. 목표 아키텍처

### 4.1 전체 구조

```text
[사용자 브라우저]
        │ HTTPS
        ▼
[Keycloak] ── SSO · MFA · RBAC
        │
        ▼
┌────────────────────────────────────────────┐
│          FastAPI eQMS Core                 │
│  ├── AuditContextMiddleware (요청ID·IP·UA) │
│  ├── Audit Service (해시체인)              │
│  ├── 문서승인 / 변경관리 / CAPA / 교육     │
│  ├── RTM / 규제모니터링 / 영향도평가       │
│  └── RAG Query Router                      │
└────────────────────────────────────────────┘
        │
        ├── [PostgreSQL Primary/Standby] ── 업무 데이터 + Audit Trail
        ├── [MinIO WORM / Nextcloud] ───── 원본 PDF · 서명 PDF
        ├── [DSS Service] ──────────────── PAdES 서명 · 검증
        ├── [Haystack + Qdrant + Ollama] ─ 승인 SOP RAG
        └── [Odoo] ─────────────────────── 생산·구매·재고·출하 운영기록
```

### 4.2 기술 스택

| 영역 | 선정 스택 | 선정 근거 |
|---|---|---|
| 웹 프레임워크 | FastAPI (Python) | 감사추적 미들웨어 용이, 타입 안전성 |
| 데이터베이스 | PostgreSQL 16+ (Patroni + PgBouncer 이중화) | 오픈소스 eQMS 표준, 트리거 기반 감사 |
| 무결성 저장소 | MinIO (S3 호환) WORM 버킷 | 원본 덮어쓰기 방지, 기록보존 |
| 문서 협업 | Nextcloud (WebDAV) | 버전관리·공유 |
| IAM | Keycloak (OIDC/SAML) | 11.10(d) 접근제한, MFA |
| 전자서명 | EU DSS (esig/dss-demonstrations, REST) | PAdES 생성·확장·검증 지원 |
| RAG | Haystack 2.x + Qdrant | 색인·검색 파이프라인, 메타데이터 필터 |
| 임베딩 | BAAI/bge-small-en-v1.5 (384차원) | 경량 온프레미스 |
| LLM | Ollama + Llama 3.1 8B / Llama3.1-Aloe-Beta-8B | 온프레미스 추론, 의료 도메인 |
| 문서 파싱 | PyPDF / Unstructured.io | PDF·Word·Excel |
| 알림 | SMTP + Slack Incoming Webhook | 규제 변경·승인 알림 |

### 4.3 Odoo ↔ Nextcloud 연동: **FastAPI 중계형** 채택

```text
Odoo → FastAPI → Nextcloud
Odoo → FastAPI → PostgreSQL Audit Trail
FastAPI → DSS → Signed PDF → Nextcloud → MinIO WORM
```

**채택 근거**
- 모든 문서 업로드·다운로드·승인·서명이 감사추적에 기록됨
- Nextcloud 권한과 eQMS 권한을 단일 정책으로 관리 가능
- Odoo 품질기록과 문서 버전의 정합성 유지
- RAG 색인 대상을 승인 완료 상태로 제한 가능

**대안 비교**

| 방식 | 장점 | 주의점 |
|---|---|---|
| WebDAV 직접 연동 | 실시간성, 단순 구조 | 네트워크·인증 관리 |
| Odoo 문서 허브 모듈 | 레코드 단위 권한 유지 | 모듈 검증 필요 |
| 주기 동기화 | webhook 불가 환경 적합 | 실시간성 제한 |
| **FastAPI 중계 (채택)** | 감사추적·권한 통제 용이 | 개발 범위 증가 |

### 4.4 저장소 폴더 구조

```text
/GMP/
 ├── SOP/
 │    └── SOP-QA-001/
 │         ├── v1.0_Draft.pdf
 │         ├── v1.0_Approved.pdf
 │         └── v2.0_Draft.pdf
 ├── DMR/      └── MDF-DEV-001/
 ├── CAPA/     └── CAPA-2026-001/
 └── DesignFile/ └── DF-PRJ-001/
```

---

## 5. 데이터 모델 총괄

### 5.1 도메인별 테이블 맵

| 도메인 | 주요 테이블 | Part 11 통제 포인트 |
|---|---|---|
| 사용자 | `users` | RBAC, 계정 비활성화 |
| 문서 | `documents`, `document_versions`, `document_approvals`, `files` | 문서번호 유일성, 버전 불변성, SHA-256 |
| 감사 | `audit_events` | append-only, 해시체인 |
| 서명 | `signatures` | 서명자·시각·의미 연결 |
| CAPA | `nonconformances`, `capa_records`, `capa_actions`, `capa_documents` | 종결 제약 트리거 |
| 교육 | `training_courses`, `training_course_versions`, `training_assignments`, `training_completions`, `training_audit_events` | 이수기록 append-only |
| 추적성 | `requirements`, `design_items`, `test_cases`, `test_executions`, `traceability_links` | URS↔설계↔시험 양방향 |
| 설계 | `design_projects`, `design_records`, `design_traceability` | ISO 13485 7.3 |
| 제품기준 | `medical_device_files`, `mdf_sections` | ISO 13485 4.2.3 |
| 규제감시 | `regulatory_sources`, `regulatory_updates`, `regulatory_impact_assessments`, `csv_revalidations`, `vsr_revisions`, `notification_logs`, `regulatory_audit_events` | 변경 감지→재검증 추적 |

### 5.2 감사추적 핵심 스키마

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE audit_events (
    audit_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_uuid    UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type   VARCHAR(50) NOT NULL,
    object_id     UUID NOT NULL,
    action        VARCHAR(30) NOT NULL,
    before_state  JSONB,
    after_state   JSONB,
    actor_id      UUID,
    actor_ip      INET,
    user_agent    TEXT,
    reason        TEXT,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    prev_hash     CHAR(64),
    record_hash   CHAR(64) NOT NULL
);

CREATE INDEX idx_audit_object ON audit_events(object_type, object_id, occurred_at DESC);
CREATE INDEX idx_audit_actor  ON audit_events(actor_id, occurred_at DESC);
CREATE INDEX idx_audit_action ON audit_events(action, occurred_at DESC);
```

**불변성 보장 — 트리거 방식 채택**

```sql
CREATE OR REPLACE FUNCTION reject_audit_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_events is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
END; $$;

CREATE TRIGGER trg_audit_no_mutation
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION reject_audit_mutation();
```

> **설계 결정**: 초기 문서(P-eQMS-02/03)의 `CREATE RULE ... DO INSTEAD NOTHING` 방식은 **조용히 무시**되어 시도 자체가 탐지되지 않는다. 본 계획은 **예외를 발생시키는 트리거 방식**(P-eQMS-04/05)을 표준으로 채택한다. OQ-AT-002 시험이 "차단 확인"을 요구하므로 예외 발생이 증적 확보에 유리하다.

**해시체인 검증 쿼리**

```sql
WITH ordered_audit AS (
    SELECT audit_id, object_type, object_id, occurred_at, prev_hash, record_hash,
           LAG(record_hash) OVER (
               PARTITION BY object_type, object_id ORDER BY occurred_at, audit_id
           ) AS expected_prev_hash
    FROM audit_events
)
SELECT audit_id, object_type, object_id, occurred_at,
       CASE WHEN prev_hash IS NOT DISTINCT FROM expected_prev_hash
            THEN 'VALID' ELSE 'INVALID' END AS chain_status
FROM ordered_audit
ORDER BY object_type, object_id, occurred_at;
```

### 5.3 이중 기록 원칙

| 계층 | 기록 책임 | 구현 |
|---|---|---|
| DB 트리거 | 데이터 변경 **자체** | `fn_insert_audit_event()` 공통 함수 + 테이블별 트리거 |
| FastAPI 미들웨어 | 사용자·IP·User-Agent·**변경 사유**·비즈니스 맥락 | `AuditContextMiddleware` + `write_audit()` |

민감정보 마스킹 대상: `password`, `token`, `secret`, `pin`, `private_key`, `keystore_password`

---

## 6. 단계별 구축 로드맵

### 6.1 전체 로드맵

| 단계 | 기간 | 목표 | 핵심 산출물 |
|---|---:|---|---|
| **Phase 0. 준비** | 2~4주 | 범위·역할·위험도 정의 | 시스템 인벤토리, GAMP 분류, URS 초안, Scope/RACI, 환경 분리 |
| **Phase 1. MVP** | 4주 | 감사추적·문서버전·전자서명·RAG 최소동작 | audit_events, 문서 API, PAdES PoC, RAG 파일럿 |
| **Phase 2. Part 11 완성** | 6~10주 | 전자서명·접근통제·기록무결성 | RBAC, 백업·복구, IQ/OQ 1차 |
| **Phase 3. 품질운영** | 8~12주 | NC/CAPA/교육/내부감사 | CAPA 워크플로, 교육 자동할당 |
| **Phase 4. RAG 고도화** | 6~8주 | SOP·규격 AI 비서 | 출처인용, 권한필터, 정확도 평가 |
| **Phase 5. 설계·제품기록** | 8~12주 | Design File, MDF, RTM | 설계추적성 매트릭스, MDF Index |
| **Phase 6. CSV·운영전환** | 3~4주 | 검증 완료 및 이관 | VMP~VSR 전체 패키지, Change Control |
| **지속운영** | 상시 | 규제 모니터링·변경통제 | 규제감시, 재검증, 정기검토 |

### 6.2 최소 투자 원칙

- **Phase 1은 엑셀 대체**에 집중 — 문서 등록·개정·승인·배포·회수만 먼저 전산화
- **CAPA·교육은 Phase 3**으로 이연하되, 문서 개정 시 교육 대상자 **알림**만 Phase 1에 최소 포함
- **RAG는 Phase 4**, 검색 대상은 승인 완료 문서로 한정
- **CSV는 개발 후가 아니라 개발과 병행** — URS·위험평가·테스트케이스를 상시 축적

### 6.3 Phase 0 상세 (Sprint 0, 2주)

| ID | 작업 | 산출물 | 완료 기준 |
|---|---|---|---|
| 0-1 | 시스템 범위·역할 정의 | Scope Statement, RACI | 품질·IT·개발 책임자 승인 |
| 0-2 | URS 초안 작성 | URS-v0.1 | 문서등록·버전·승인·감사추적·배포 요구 포함 |
| 0-3 | 위험평가 | Risk Assessment Matrix | 고위험 기능 식별 및 통제 정의 |
| 0-4 | 환경 구성 | dev/staging/prod 분리 | Local 개발 환경과 사내 AX 서버 분리 |
| 0-5 | 저장소·CI 구성 | Git, Docker Compose, CI | 코드·마이그레이션·테스트 자동 실행 |

### 6.4 Phase 1 상세 (4주 MVP)

| 주차 | 목표 | 완료 기준 |
|---|---|---|
| **1주차** | 감사추적 PoC | 감사기록 생성, UPDATE/DELETE 차단, 해시체인 검증 통과 |
| **2주차** | 문서등록·버전관리 API | 문서·버전 생성, SHA-256 재계산 일치 |
| **3주차** | DSS PAdES 서명 PoC | 서명 생성·검증 성공, 변조 시 검증 실패 확인 |
| **4주차** | RAG 파일럿 | 승인 SOP 10~20건 색인, 권한 필터 검색, 정확도 평가 |

**1주차 일별 계획 (감사추적 PoC)**

| Day | 작업 | 산출물 |
|---:|---|---|
| 1 | PostgreSQL 스키마·트리거 생성 | `audit_events` 테이블 |
| 2 | SQLAlchemy 모델·DB 세션 구성 | ORM 모델 |
| 3 | FastAPI 감사추적 서비스 구현 | `app/core/audit.py` |
| 4 | 문서 API에 감사추적 연결 | 문서 생성·수정 API |
| 5 | 무결성 테스트 | UPDATE/DELETE 차단, 해시 검증 |
| 6 | 감사조회 API | 기간·객체·사용자 필터 |
| 7 | PoC 보고서 | 테스트 결과·제한사항 |

**3주차 DSS 서명 PoC 절차**

| 단계 | 작업 | 확인 항목 |
|---:|---|---|
| 1 | 샘플 SOP PDF 준비 | 문서번호·버전·작성자 포함 |
| 2 | DSS REST API 서명 요청 | PAdES 서명 생성 |
| 3 | 서명 PDF 저장 | MinIO / Nextcloud |
| 4 | 서명 검증 API 호출 | 유효성·무결성 |
| 5 | 감사추적 기록 | 서명자·시각·서명의미 |
| 6 | 원문 변조 테스트 | 변조 시 검증 실패 |

### 6.5 Phase 1 스프린트 백로그 (MVP 세분화)

**Sprint 1: 문서등록 및 버전생성**

| ID | User Story | 수용기준 |
|---|---|---|
| 1-1 | 품질담당자는 SOP를 등록할 수 있다 | 문서번호·제목·유형·소유부서·유효일 입력 |
| 1-2 | 시스템은 문서번호를 자동 부여한다 | 중복 없음, 규칙 기반 생성 |
| 1-3 | 신규 버전을 생성할 수 있다 | 기존 버전 SUPERSEDED, 신규 DRAFT |
| 1-4 | 시스템은 파일 해시를 생성한다 | SHA-256 저장, 재계산 일치 |
| 1-5 | 관리자는 문서 현황을 조회한다 | 상태별 필터, 버전 이력 |

**Sprint 2: 승인요청 및 감사추적**

| ID | User Story | 수용기준 |
|---|---|---|
| 2-1 | 작성자는 승인요청을 생성한다 | 승인자·역할·기한 지정 |
| 2-2 | 승인자는 승인 또는 반려한다 | 사유 필수, 상태 변경 기록 |
| 2-3 | 시스템은 모든 행위를 감사추적한다 | 생성·수정·조회·승인·반려 기록 |
| 2-4 | 감사추적은 수정·삭제 불가 | 트리거로 차단 |
| 2-5 | 감사담당자는 이력을 조회한다 | 객체·사용자·기간별 검색 |

**Sprint 3: 배포 및 교육 알림**

| ID | User Story | 수용기준 |
|---|---|---|
| 3-1 | 승인 완료 문서를 배포한다 | 유효일 시작, 구버전 회수 |
| 3-2 | 관련 부서에 변경 알림 발송 | 이메일 또는 사내 메신저 |
| 3-3 | 교육 대상자를 지정한다 | 문서유형·역할 기반 자동 지정 |
| 3-4 | 배포 이력을 조회한다 | 배포일·대상·확인 여부 |
| 3-5 | 문서 개정 시 구버전 접근 제한 | 권한별 조회 통제 |

**Sprint 4: CSV 준비 및 MVP 검증**

| ID | 작업 | 산출물 |
|---|---|---|
| 4-1 | URS 확정 | URS-v1.0 |
| 4-2 | 기능 위험도 평가 | Risk Control Matrix |
| 4-3 | IQ/OQ 테스트케이스 작성 | Test Protocol |
| 4-4 | 감사추적·버전·승인 테스트 수행 | Test Evidence |
| 4-5 | MVP 검증보고서 작성 | MVP Validation Summary |

### 6.6 확장 우선순위

| 우선순위 | 모듈 | 이유 |
|---:|---|---|
| 1 | CAPA | NC→CAPA→효과성 확인이 품질시스템의 핵심 |
| 2 | 교육 | 문서개정 시 교육할당 자동화 필요 |
| 3 | 설계추적성 | Design File·RTM으로 규제 대응 강화 |
| 4 | CSV 패키지 | 감사 대응 및 운영전환 승인 |
| 5 | Odoo·Nextcloud 연동 | 품질기록과 문서 원본 통합 |

---

## 7. 모듈별 구현 사양

### 7.1 문서관리 · 버전관리

**상태 전이 규칙**

| 현재 상태 | 허용 행위 | 다음 상태 | 감사 action |
|---|---|---|---|
| DRAFT | 제출 | IN_REVIEW | SUBMIT |
| IN_REVIEW | 승인 서명 | APPROVED | SIGN |
| IN_REVIEW | 반려 | REJECTED | REJECT |
| APPROVED | 배포 | EFFECTIVE | DEPLOY |
| EFFECTIVE | 신규 버전 생성 | SUPERSEDED | CREATE_VERSION |

**핵심 API**

| API | Method | 기능 |
|---|---|---|
| `/api/documents` | POST | 문서 등록 |
| `/api/documents/{id}/versions` | POST | 신규 버전 등록 |
| `/api/documents/{id}/submit` | POST | 승인 요청 |
| `/api/approvals/{id}/sign` | POST | 전자서명·승인 |
| `/api/change-requests` | POST | 변경요청 생성 |
| `/api/audit-events` | GET | 감사기록 조회 |
| `/api/rag/ask` | POST | SOP 질의응답 |

### 7.2 전자서명 (DSS PAdES)

**구성**: `esig/dss-demonstrations` 이미지를 별도 REST 서비스로 기동 (Python 백엔드에서 호출하는 방식이 유지보수에 유리)

**주요 엔드포인트**
- 서명: `POST {DSS}/services/rest/signature/one-document/signDocument`
- 검증: `POST {DSS}/services/rest/validation/validateDocument`

**요청 파라미터**: `signatureForm=PAdES`, `packaging=ENVELOPED`, `digestAlgorithm=SHA256`, `keyAlias`, `keystorePassword`, `signatureMeaning`

**서명 권한**: `QA_REVIEWER`, `QA_APPROVER` 역할만 허용
**서명 의미**: `REVIEW` | `APPROVAL` | `RESPONSIBILITY` 중 하나로 제한 검증

**검증 포인트**
- 서명자 이름·서명 시각·서명 의미가 전자기록과 연결되는가
- 서명 후 PDF 원문 변경 시 검증이 실패하는가
- 서명 기록이 `audit_events`에 남는가
- 서명된 PDF가 MinIO/Nextcloud에 저장되는가

### 7.3 CAPA 관리

**프로세스**: NC 발생 → NC 등록 → CAPA 생성 → 원인분석 → 시정/예방조치 계획 → 조치 실행 → 효과성 확인 → CAPA 종결

**종결 제약 (트리거로 강제)** — `fn_validate_capa_closure()`
1. 미완료 조치(`status NOT IN ('COMPLETED','VERIFIED')`)가 존재하면 종결 차단
2. `EFFECTIVENESS_CHECK` 유형 조치가 `VERIFIED` 상태로 1건 이상 없으면 차단
3. `effectiveness_check` 결과 텍스트가 비어 있으면 차단

**원인분석 방법**: 5WHY / FISHBONE / FMEA / FTA / OTHER
**NC 소스**: INTERNAL_AUDIT / CUSTOMER_COMPLAINT / PRODUCTION / SUPPLIER / REGULATORY / OTHER
**심각도**: LOW / MEDIUM / HIGH / CRITICAL

**감사 트리거**: `capa_records`, `nonconformances`, `capa_actions` 3개 테이블 모두 INSERT/UPDATE/DELETE 감사

### 7.4 교육·이수관리

**프로세스**: 문서 승인 → 교육과정 버전 연결 → 대상 역할 자동 할당 → 교육 이수 → 평가·인증서 발급 → 감사추적 기록

**설계 원칙**
- 교육과정 / 교육버전 / 할당 / 이수기록을 **분리**
- 문서 승인 시 `target_roles` 기준 자동 할당 (기본 기한: 승인일 +14일)
- 이수기록은 append-only, 재교육은 **신규 이수기록**으로 생성
- 교육기록은 사용자·과정·문서버전·이수일·평가·인증서와 연결

**자동 할당 트리거**: `trg_assign_training_on_approval` (`document_versions` AFTER UPDATE, `status='APPROVED'` 시)

### 7.5 설계추적성 (RTM)

**추적 체인**

```text
Regulatory Requirement → User Need → System Requirement
  → Design Specification → Implementation
  → Test Case → Test Execution → Validation Evidence
```

**관계 유형**: `TRACES_TO` / `IMPLEMENTED_BY` / `VERIFIED_BY` / `VALIDATED_BY` / `MITIGATED_BY` / `DERIVES_FROM`

**필수 운영 쿼리**
1. **RTM 전체 조회** — 요구사항↔설계↔시험↔결과↔증적 1행 조회
2. **미커버 요구사항 리포트** — `VERIFIED_BY` 링크가 0건인 요구사항 추출 (우선순위 역순 정렬)

**RTM 예시**

| URS ID | 위험 ID | 설계 ID | 시험 ID | 결과 | 증적 | 규제 참조 |
|---|---|---|---|---|---|---|
| URS-DC-001 | R-003 | DS-DOC-001 | OQ-DOC-001 | PASS | evidence_001.pdf | 21 CFR Part 11 |
| URS-AT-001 | R-001 | DS-AT-001 | OQ-AT-001 | PASS | evidence_002.pdf | 21 CFR Part 11 |
| URS-AT-002 | R-001 | DS-AT-002 | OQ-AT-002 | PASS | evidence_003.pdf | 21 CFR Part 11 |
| URS-SIG-001 | R-002 | DS-SIG-001 | OQ-SIG-001 | PASS | evidence_004.pdf | 21 CFR Part 11 |
| URS-SIG-002 | R-002 | DS-SIG-002 | OQ-SIG-002 | PASS | evidence_005.pdf | 21 CFR Part 11 |
| URS-CAPA-003 | R-006 | DS-CAPA-003 | OQ-CAPA-003 | PASS | evidence_006.pdf | ISO 13485 |
| URS-TRN-003 | R-007 | DS-TRN-003 | OQ-TRN-003 | PASS | evidence_007.pdf | ISO 13485 |
| URS-RAG-001 | R-004 | DS-RAG-001 | OQ-RAG-001 | PASS | evidence_008.pdf | GAMP 5 |

### 7.6 설계개발 파일 · MDF

**Design and Development File 구성**

```text
DesignProject
 ├── DesignPlan        ├── UserNeeds      ├── DesignInputs
 ├── DesignOutputs     ├── RiskFile (ISO 14971)
 ├── DesignReviews     ├── V&VRecords
 ├── DesignTransfer    └── DesignChanges
```

**MDF 섹션 유형**: `DEVICE_SPEC` / `PROCESS_SPEC` / `QA_PROCEDURE` / `PACKAGING_LABELING` / `INSTALLATION_MAINTENANCE_SERVICE`

**추적성 화면**

| 화면 | 핵심 기능 |
|---|---|
| Design Traceability Matrix | User Need → Input → Output → Risk → V&V → Change 연결 |
| MDF Index | 제품별 사양·절차·라벨링·서비스 문서 일괄 조회 |
| Change Impact | 문서 개정 시 영향받는 설계·MDF·CAPA 자동 표시 |
| Audit Viewer | 기록별 생성·수정·승인·서명 이력 조회 |

### 7.7 보안형 RAG 파이프라인

**색인 파이프라인**: PyPDFToDocument → DocumentCleaner → DocumentSplitter(300 word / 50 overlap) → SentenceTransformersDocumentEmbedder → DocumentWriter(Qdrant)

**임베딩 메타필드**: `doc_no`, `title`, `version`, `status`, `effective_date`, `owner_department`, `access_roles`

**질의 파이프라인**: TextEmbedder → QdrantEmbeddingRetriever(top_k=5, 필터) → PromptBuilder → OllamaChatGenerator

**검색 필터 (필수)**

```python
filters = {
    "operator": "AND",
    "conditions": [
        {"field": "meta.status", "operator": "==", "value": "APPROVED"},
        {"field": "meta.access_roles", "operator": "in", "value": current_user.roles},
    ],
}
```

**응답 정책**
1. 제공된 내부 문서 근거만 사용
2. 근거 없으면 "확인된 내부 문서 근거가 없습니다"로 응답
3. 문서번호·제목·버전·유효일 반드시 인용
4. 최종 판단·승인은 품질담당자가 수행함을 명시
5. 질의·검색 문서·응답 요약을 감사추적에 기록
6. 비밀번호·토큰·서명 PIN은 로그 마스킹

**평가 기준**

| 항목 | 정의 | 측정 | 통과 기준 |
|---|---|---|---|
| 정확성 | 답변이 SOP 내용과 일치 | 전문가 3점 척도 | 80% 이상 |
| 출처일치 | 인용 문서·버전이 실제 근거 | 출처 대조 | 100% |
| 완결성 | 필요 내용 누락 없음 | 누락 항목 수 | — |
| 환각률 | 근거 없는 문장 비율 | 근거없는 문장/전체 | 10% 미만 |
| 검색 재현율 | 정답 문서 Top-5 포함 | Hit@5 | — |

**파일럿 범위**: 승인 SOP 10~20건, 품질담당자 3~5명, 문서당 5~10개 질문

### 7.8 규제 변경 모니터링 및 자동 영향도 평가

**운영 흐름**

```text
[규제 소스] → [모니터링 스크립트] → [변경 감지 + 키워드 분류]
   → [규제 변경 로그 저장] → [자동 영향도 평가]
        ├── URS 영향  ├── RTM 영향  ├── CAPA 영향
        ├── 교육 영향 └── CSV 재검증 필요성
   → [변경관리 + 재검증] → [VSR 갱신 + 운영 승인] → [Slack·이메일 알림]
```

**모니터링 대상**

| 대상 | 소스 | 주기 |
|---|---|---|
| FDA Guidance | FDA Guidance Documents 검색 페이지 | 주 1회 |
| 21 CFR Part 11 | eCFR Title 21 Part 11 | 주 1회 |
| FDA QMSR / 21 CFR 820 | eCFR Title 21 Part 820 | 주 1회 |
| GAMP 5 | ISPE 공지·GAMP 뉴스 | 월 1회 |
| EU Annex 11 | EudraLex Volume 4 | 월 1회 |
| ISO 13485 | ISO 업데이트 공지 | 분기 1회 |

**감지 방식**: 페이지 SHA-256 해시 비교 + 키워드 필터 (해시 변경 **AND** 키워드 매칭 시에만 알림)

**자동 영향도 평가 규칙**

| 키워드 | 영향 대상 | 판정 | 재검증 범위 |
|---|---|---|---|
| `electronic signatures` | URS-SIG, RTM, DSS | MAJOR_IMPACT | TARGETED |
| `audit trail` | URS-AT, DB, RTM | MAJOR_IMPACT | TARGETED |
| `data integrity` | URS-AT, 백업, 감사추적 | MAJOR_IMPACT | TARGETED |
| `computer software assurance` | VMP, Risk, RTM | MINOR_IMPACT | TARGETED |
| `design and development` | URS-RTM, Design File | MAJOR_IMPACT | TARGETED |
| `medical device file` | URS-DC, DMR/MDF | MINOR_IMPACT | TARGETED |
| `validation` | VMP, OQ/PQ, VSR | MINOR~MAJOR | TARGETED |
| `training` | 교육모듈, SOP | MINOR_IMPACT | NONE |
| `quality management system regulation` | 전체 QMS | MAJOR_IMPACT | FULL |

**판정 합산 규칙**: 결론은 MAJOR > MINOR > NO_IMPACT 우선, 범위는 FULL > TARGETED > NONE 우선. `csv_revalidation_required = (scope != 'NONE')`

**재검증 워크플로**: 영향도 평가 → 재검증 필요성 판단(NO_IMPACT 종결 / TARGETED / FULL) → 변경관리 개시 → 재검증 계획 수립(기본 30일) → IQ/OQ/PQ 재실행 → 편차 처리 → VSR 갱신 → QA 승인

**알림 채널**: 이메일(SMTP) + Slack Incoming Webhook (`AsyncWebhookClient`), 발송 성공·실패를 `notification_logs`에 기록

---

## 8. CSV 검증 전략

### 8.1 CSV 패키지 구성

| 문서 | 목적 | 작성 시점 |
|---|---|---|
| **VMP** | 검증 전략·범위·역할 정의 | 프로젝트 시작 |
| **URS** | 사용자·규제 요구사항 정의 | 요구사항 확정 |
| **Risk Assessment** | 기능별 위험·통제 정의 | URS 이후 |
| **RTM** | URS-위험-설계-시험 연결 | 테스트 설계 |
| **IQ Protocol** | 설치·환경·구성 검증 | 설치 전 |
| **OQ Protocol** | 기능·경계·오류조건 검증 | 개발 완료 후 |
| **PQ Protocol** | 실제 업무 시나리오 검증 | 운영 전 |
| **Test Evidence** | 실행결과·스크린샷·로그 | 테스트 실행 |
| **Deviation Log** | 편차·원인·조치·재시험 | 편차 발생 |
| **VSR** | 검증요약·잔여리스크·운영승인 | 검증 완료 |
| **SOP** | 운영·백업·장애·변경절차 | 운영 전 |
| **Training Record** | 사용자 교육·이수 증적 | 운영 전 |

### 8.2 작성 순서

```text
1. VMP 작성              7. 테스트 실행 및 증적 수집
2. URS 작성 및 승인       8. 편차 처리
3. 위험평가 수행          9. VSR 작성
4. 기능명세·설계문서 작성 10. SOP·교육기록 완비
5. RTM 작성              11. 운영전환 승인
6. IQ/OQ/PQ 프로토콜 작성
```

### 8.3 역할 및 책임

| 역할 | 책임 |
|---|---|
| QA Owner | URS 승인, 검증결과 승인 |
| System Owner | 운영환경 승인 |
| IT Validation | IQ/OQ 실행 |
| Business User | PQ 실행 |
| Auditor | 검증증적 검토 |

### 8.4 URS 요구사항 기준선

요구사항 분류: **FR**(Functional) / **NFR**(Non-Functional) / **CR**(Compliance) / **SR**(Security)

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증 |
|---|---|---|---|---|---|
| URS-DC-001 | FR | 사용자는 SOP를 등록할 수 있다 | 문서번호·제목·유형·소유자 저장 | High | OQ |
| URS-DC-002 | FR | 신규 버전을 생성할 수 있다 | 구버전 SUPERSEDED 처리 | High | OQ |
| URS-DC-003 | FR | 문서는 승인 후 배포된다 | 승인 전 배포 불가 | High | OQ |
| URS-AT-001 | CR | 생성·수정·승인 행위는 감사추적된다 | 감사기록 생성 | High | OQ |
| URS-AT-002 | CR | 감사기록은 수정·삭제될 수 없다 | UPDATE/DELETE 차단 | High | OQ |
| URS-AT-003 | CR | 감사기록은 사용자·시각·사유를 포함한다 | 필수 필드 존재 | High | OQ |
| URS-SIG-001 | CR | 승인자는 PAdES 전자서명을 수행한다 | 서명·검증 성공 | High | OQ |
| URS-SIG-002 | CR | 서명 후 원문 변경은 탐지된다 | 변조 시 검증 실패 | High | OQ |
| URS-SIG-003 | CR | 서명자·시각·서명의미는 기록된다 | 서명 메타데이터 저장 | High | OQ |
| URS-CAPA-001 | FR | NC를 등록할 수 있다 | NC번호·심각도·소유자 저장 | High | OQ |
| URS-CAPA-002 | FR | NC에서 CAPA를 생성할 수 있다 | NC-CAPA 연결 | High | OQ |
| URS-CAPA-003 | CR | CAPA 종결 시 효과성 확인이 필요하다 | 미완료 조치 시 종결 차단 | High | OQ |
| URS-TRN-001 | FR | 문서 승인 시 교육을 할당한다 | 대상자별 교육기록 생성 | Medium | OQ |
| URS-TRN-002 | FR | 교육 이수 여부를 관리한다 | 이수일·평가·상태 저장 | Medium | OQ |
| URS-TRN-003 | CR | 교육기록은 변경·삭제될 수 없다 | append-only 기록 | High | OQ |
| URS-RTM-001 | FR | 요구사항을 설계·시험과 연결한다 | RTM 관계 저장 | High | OQ |
| URS-RTM-002 | FR | 요구사항-시험 커버리지를 확인한다 | 미커버 요구사항 리포트 | High | OQ |
| URS-RAG-001 | FR | 승인 SOP를 검색할 수 있다 | 승인 문서만 검색 | Medium | OQ |
| URS-RAG-002 | FR | 근거 없는 질문에 근거 없음을 응답한다 | 환각 방지 응답 | Medium | OQ |
| URS-RAG-003 | CR | 검색 질의와 출처는 감사추적된다 | 질의·문서·응답 기록 | High | OQ |
| URS-INF-001 | NFR | 서버·OS는 승인 사양과 일치한다 | 사양 일치 | High | IQ |
| URS-INF-002 | NFR | PostgreSQL 16 이상을 사용한다 | 버전 확인 | High | IQ |
| URS-STG-001 | SR | 원본 문서 덮어쓰기를 방지한다 | WORM 정책 확인 | High | IQ |
| URS-AT-004 | NFR | 서버 시간은 동기화된다 | NTP 오차 허용범위 내 | High | IQ |

### 8.5 위험평가 기준선

| Risk ID | 기능 | 위험 | 영향 | 심각도 | 발생 | 위험도 | 통제 | 검증 |
|---|---|---|---|---:|---:|---|---|---|
| R-001 | 감사추적 | 감사기록 삭제 | 규제 기록 손실 | 5 | 2 | High | append-only 트리거 | OQ-AT-002 |
| R-002 | 전자서명 | 무단 서명 | 무효 승인 | 5 | 2 | High | RBAC + 인증서 | OQ-SIG-001 |
| R-003 | 문서버전 | 구버전 덮어쓰기 | 이력 상실 | 4 | 3 | High | 버전 불변 설계 | OQ-DOC-002 |
| R-004 | RAG | 비승인 문서 검색 | 잘못된 품질 판단 | 4 | 3 | High | status 필터 | OQ-RAG-001 |
| R-005 | RAG | 근거 없는 답변 | 오해 유발 | 4 | 3 | High | 근거 없음 정책 | OQ-RAG-002 |
| R-006 | CAPA | 효과성 미확인 종결 | 재발 | 4 | 3 | High | 종결 제약 트리거 | OQ-CAPA-003 |
| R-007 | 교육 | 이수기록 변조 | 교육 증적 상실 | 4 | 2 | High | append-only 트리거 | OQ-TRN-003 |

### 8.6 IQ 프로토콜 항목

| ID | 시험 항목 | URS | 시험방법 | 기대결과 |
|---|---|---|---|---|
| IQ-001 | 서버 및 OS 확인 | URS-INF-001 | 사양·OS 버전 확인 | 승인 사양 일치 |
| IQ-002 | PostgreSQL 설치 확인 | URS-INF-002 | `SELECT version();` | PostgreSQL 16 이상 |
| IQ-003 | 감사추적 테이블 확인 | URS-AT-001 | 테이블·인덱스·트리거 확인 | 모든 객체 존재 |
| IQ-004 | MinIO WORM 설정 확인 | URS-STG-001 | 버킷 정책·버전관리 확인 | 원본 덮어쓰기 방지 |
| IQ-005 | DSS 서비스 접속 확인 | URS-SIG-001 | DSS REST 헬스체크 | HTTP 200 |
| IQ-006 | 시간동기화 확인 | URS-AT-004 | NTP 동기화 상태 | 오차 허용범위 내 |

### 8.7 OQ 프로토콜 항목

| ID | 시험 항목 | URS | 기대결과 |
|---|---|---|---|
| OQ-DOC-001 | 문서 등록 | URS-DC-001 | 문서 생성 + 감사기록 1건 |
| OQ-DOC-002 | 신규 버전 생성 | URS-DC-002 | 구버전 SUPERSEDED, 신규 DRAFT |
| OQ-AT-001 | 감사추적 생성 | URS-AT-001 | CREATE·UPDATE 기록 존재 |
| OQ-AT-002 | 감사추적 변경 차단 | URS-AT-002 | UPDATE·DELETE 모두 차단 |
| OQ-SIG-001 | PAdES 전자서명 | URS-SIG-001 | 서명·검증 성공 |
| OQ-SIG-002 | 서명 후 변조 탐지 | URS-SIG-002 | 검증 실패 |
| OQ-CAPA-003 | CAPA 종결 제약 | URS-CAPA-003 | 두 경우 모두 차단 |
| OQ-TRN-003 | 교육기록 불변성 | URS-TRN-003 | 변경·삭제 차단 |
| OQ-RAG-001 | 승인 문서만 검색 | URS-RAG-001 | APPROVED만 검색 |
| OQ-RAG-002 | 근거 없는 질문 처리 | URS-RAG-002 | "근거 없음" 응답 |

### 8.8 PQ 시나리오

| ID | 시나리오 | 수용기준 |
|---|---|---|
| **PQ-001** | SOP 개정 전 과정: v1.0 등록 → 검토 → PAdES 서명 → 유효일 설정·배포 → RAG 검색 → v2.0 생성 → v1.0 SUPERSEDED | 모든 상태 전이·서명 기록, 감사추적 완전성, 승인 문서만 검색 |
| **PQ-002** | CAPA 문서 연계: Odoo CAPA 생성 → FastAPI 문서 등록 → Nextcloud 저장 → 승인·서명 → 감사추적 확인 | CAPA ID-문서 ID 연결, 원본·서명본 구분 저장, 감사기록 완전성 |
| **PQ-003** | RAG 사용성 평가 (품질담당자 3~5명, 문서당 5~10문항) | 정확성 80%↑, 환각률 10%↓, 출처·버전 표시 100% |
| **PQ-004** | 백업 및 복구: DB·원본 백업 → 장애 시뮬레이션 → 복구 | DB·문서 원본 복구 성공, 감사추적 연속성 |

### 8.9 수용 기준 (Release Criteria)

- High Risk 테스트 **100% 통과**
- 모든 URS에 대응 테스트 존재 (미커버 요구사항 0건)
- 편차 없음 또는 **승인된 편차만** 존재
- 감사추적 해시체인 검증 통과
- 전자서명 변조 탐지 테스트 통과
- RAG가 승인 문서만 검색하고 출처 인용
- 교육기록·SOP·백업복구 증적 완비

### 8.10 VSR 필수 구성

VSR은 **시스템·범위, 프로토콜·수용기준, 결과, 편차, 미해결 항목, 추적성 확인, 릴리스 판정, 승인자 서명**을 포함해야 하며, 조건부 승인도 문서화된 위험 평가를 전제로 허용된다.

릴리스 판정: `Validated` / `Validated with restrictions` / `Not validated`

---

## 9. 운영 거버넌스 및 변화관리

### 9.1 운영 SOP 목록

| SOP | 내용 |
|---|---|
| SOP-EQMS-001 | 문서 등록·개정·승인·배포 절차 |
| SOP-EQMS-002 | 감사추적 조회·검증 절차 |
| SOP-EQMS-003 | 전자서명 발급·사용·폐기 절차 |
| SOP-EQMS-004 | RAG 검색·출처확인·환각 대응 절차 |
| SOP-EQMS-005 | 백업·복구·장애 대응 절차 |
| SOP-EQMS-006 | 변경관리·CSV 재검증 절차 |

### 9.2 변경통제 (Change Control)

- 개발(Local) → 검증(Staging) → 운영(사내 AX 서버) 이관 시 **이관계획·테스트결과·승인기록** 보관
- 변경 발생 시 영향평가 → 재검증 범위 판정 → VSR 개정
- 연차 **정기검토(Periodic Review)** 계획 수립, CAPA·내부감사와 연동

### 9.3 교육기록

| 교육 ID | 대상자 | 교육문서 | 교육일 | 이수일 | 평가 | 승인자 |
|---|---|---|---|---|---|---|
| TRN-001 | | SOP-EQMS-001 | | | | |
| TRN-002 | | SOP-EQMS-002 | | | | |
| TRN-003 | | SOP-EQMS-003 | | | | |

### 9.4 저장소 구조

```text
medical-eqms/
├── backend/
│   ├── app/
│   │   ├── core/         (config, database, security, audit, middleware)
│   │   ├── models/ schemas/ routers/ services/
│   │   └── main.py
│   ├── alembic/  tests/  pyproject.toml
├── rag/
│   ├── indexing_pipeline.py  query_pipeline.py  evaluation/
├── regulatory/
│   ├── sources.py  monitor.py  scheduler.py
├── dss/
│   ├── docker-compose.dss.yml  postman/
├── docs/
│   ├── VMP.md  URS.md  Risk_Assessment.md  RTM.md
│   ├── IQ_OQ_PQ.md  Validation_Report.md
├── docker-compose.yml
└── README.md
```

### 9.5 컨테이너 구성

| 서비스 | 이미지/빌드 | 포트 |
|---|---|---|
| api | ./backend | 8000 |
| db | postgres:16 | 5432 |
| minio | minio/minio | 9000 / 9001 |
| qdrant | qdrant/qdrant | 6333 |
| ollama | ollama/ollama | 11434 |
| dss | esig/dss-demonstrations | 8080 |

---

## 10. 리스크 및 완화

| 리스크 | 내용 | 완화책 |
|---|---|---|
| 오픈소스 검증 부족 | 감사기관의 오픈소스 eQMS 인정 여부 불확실 | CSV 문서(URS/IQ/OQ/PQ)로 검증증거 제출, 상용 eQMS 병행 평가 |
| Part 11 해석 | 감사추적 "불변성" 구현 난이도 | WORM 스토리지, 트리거 차단, 해시체인, 외부 감사모듈 검토 |
| LLM 환각 | RAG 기반 SOP 답변 오류 | 출처 인용 강제, "근거 없음" 응답 허용, 인간 검토 워크플로 |
| CSV 비용 | 문서작업 과다 | GAMP 5 리스크 기반 접근, Category 4 설정형 우선 |
| DSS 적용 범위 | DSS는 eIDAS·PAdES 중심 | 회사 전자서명 정책·인증서 운영·서명의미 정의를 별도 문서화 |
| 용어 전환 혼선 | DHF/DMR/DHR 명칭 소멸, 기록 요구 유지 | 기존 색인 ↔ 신규 MDF·Design File 이중 매핑표 운영 |
| 운영 중단 | DB·스토리지 장애 | Primary/Standby 이중화, PQ-004 복구 검증 |

---

## 11. 완료 기준 (Definition of Done)

| 영역 | 완료 기준 |
|---|---|
| **문서관리** | 문서번호 중복 0건, 모든 버전 이력 보존 |
| **버전관리** | 구버전 덮어쓰기 없음, SUPERSEDED 자동 처리 |
| **승인** | 승인자·시각·의미 100% 기록 |
| **감사추적** | DB 트리거 + FastAPI 이중 기록, UPDATE/DELETE 차단, 해시체인 VALID |
| **무결성** | SHA-256 재계산 100% 일치 |
| **전자서명** | PAdES 서명·검증 성공, 변조 시 검증 실패 |
| **CAPA** | NC-CAPA-조치-효과성 확인까지 추적 |
| **교육** | 문서 승인 시 자동 할당, 이수기록 append-only |
| **RTM** | URS-설계-시험-증적 양방향 연결, 미커버 0건 |
| **CSV** | VMP-URS-Risk-RTM-IQ/OQ/PQ-VSR 연결 완료 |
| **RAG** | 승인 문서만 검색, 출처·버전 인용 100% |
| **권한** | 역할 외 접근 403 반환 |
| **백업** | DB·파일 복구 테스트 통과 |
| **규제 모니터링** | FDA·GAMP·Annex 11 변경 자동 감지 및 알림, 발송 성공·실패 로그 |
| **영향도 평가** | 키워드 기반 URS·RTM·CAPA·교육 영향 식별 |
| **재검증** | TARGETED 또는 FULL 재검증 계획 생성, VSR 개정번호·사유·승인 기록 |

---

## 12. 다음 4주 실행계획

| 주차 | 목표 | 핵심 산출물 | 담당 |
|---|---|---|---|
| **1주차** | 감사추적 PoC 완성 | `audit_events` 스키마·트리거, FastAPI 미들웨어, 무결성 테스트 | 개발 + IT Validation |
| **2주차** | 문서등록·버전관리 API | 문서·버전·파일 해시 API, 상태 전이 규칙 | 개발 |
| **3주차** | DSS 서명 PoC | PAdES 서명·검증·변조 탐지·감사기록 | 개발 + QA |
| **4주차** | RAG 파일럿 준비 | 승인 SOP 10건 색인, 평가 질문 세트, 권한 필터 | 개발 + 품질담당자 |

**병행 작업 (상시)**
- URS v1.0 확정 및 QA Owner 승인
- Risk Assessment Matrix 작성
- IQ/OQ 테스트케이스 축적

**즉시 착수 항목 (Day 1)**
1. Phase 0 Scope Statement·RACI 확정 회의 소집
2. dev/staging/prod 3환경 분리 및 Git·CI 구성
3. `docker-compose.yml` 기준 로컬 스택 기동 (db, minio, qdrant, ollama, dss)
4. QAtrial / dearauditor-qms-baseline 로컬 설치 후 기능 벤치마킹 (베이스 채택 여부 판단)
5. GAMP 5 분류 확정 (모듈별 Category 4 / 5 구분표 작성)

---

## 13. 불확실성 및 추가 확인 필요 사항

| 항목 | 불확실성 | 확인 방법 |
|---|---|---|
| 오픈소스 eQMS 감사 인정 | Notified Body·FDA 검사관 수용 여부 | 실제 의료기기 업체 사례 인터뷰 |
| DSS의 Part 11 적합성 | DSS의 FDA 21 CFR Part 11 명시적 적합성 | 법적 검토·변호사 자문 |
| LLM 의료 정확도 | Aloe·OpenBioLLM의 의료기기 SOP 도메인 성능 | 사내 문서 RAG 벤치마크 |
| 국내 KGMP·UDI 연계 | 식약처 통합정보시스템 직접 연동 방식 | GMS-MD 등 국내 패키지 연동 사양 조사 (본 계획 범위 외) |
| 상용 패키지 병행 | 자체 구축 대비 TCO | Greenlight Guru·Qualio 견적 및 CSV 패키지 제공 범위 확인 |
| GAMP 5 모듈별 분류 | Category 4 / 5 경계 | QA Owner와 모듈별 분류표 합의 필요 |

---

## 14. 핵심 설계 결정 요약

| # | 결정 | 근거 |
|---|---|---|
| 1 | Odoo·Nextcloud는 운영 기반, Part 11 통제는 FastAPI 커스텀 계층으로 **분리** | 상용/오픈소스 제품이 Part 11을 보장하지 않음 |
| 2 | 감사추적 불변성은 **RULE이 아닌 TRIGGER + 예외 발생** | 차단 시도 자체가 탐지·증적화되어야 OQ 통과 |
| 3 | 감사기록은 **DB 트리거 + 애플리케이션 이중 기록** | 데이터 변경 자체 + 사용자 맥락 모두 필요 |
| 4 | Odoo-Nextcloud는 **FastAPI 중계형** 연동 | 모든 문서 행위를 감사추적에 포함 |
| 5 | RAG 검색 대상은 **status=APPROVED + access_roles 매칭**으로 이중 제한 | 비승인 문서 기반 품질 판단 방지 |
| 6 | CSV는 개발 완료 후가 아니라 **개발과 병행** 축적 | 사후 문서화 비용·누락 방지 |
| 7 | 전자서명은 DSS를 **별도 REST 서비스**로 분리 운영 | Java 라이브러리 직접 통합 대비 유지보수 유리 |
| 8 | RAG 답변은 **품질 판단 아님** — UI·SOP에 명시 | 최종 해석·승인은 담당자 책임 |

---

**승인**

| 역할 | 성명 | 서명 | 일자 |
|---|---|---|---|
| 작성자 | | | |
| 검토자 (QA Owner) | | | |
| 승인자 (System Owner) | | | |
