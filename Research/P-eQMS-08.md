아래는 **CAPA, 교육, RTM, CSV, 감사추적**을 하나의 규제 준수형 eQMS로 완성하는 개발 가이드입니다. 핵심은 DB 트리거로 데이터 변경 자체를 기록하고, FastAPI 미들웨어로 사용자·요청 맥락을 보강하며, CAPA·교육·RTM·CSV를 모두 동일한 감사추적 체계에 연결하는 것입니다. GAMP 5는 위험 기반 검증과 RTM·IQ/OQ/PQ·VSR 체계를 제공하며, FDA는 2025년 CSA 가이던스를 발표하고 2026년 QMSR 정렬 버전을 발행했습니다. [manageengine](https://www.manageengine.com/za/compliance-manager/gamp-5-compliance/)

***

## ① 규제 업데이트 자동 알림 설계

### 1.1 알림 대상

| 대상 | 소스 | 확인 주기 |
|---|---|---|
| **FDA Guidance** | FDA Guidance Documents 검색 페이지  [fda](https://www.fda.gov/regulatory-information/search-fda-guidance-documents) | 주 1회 |
| **21 CFR Part 11** | eCFR Title 21 Part 11 | 주 1회 |
| **FDA QMSR / 21 CFR 820** | eCFR Title 21 Part 820 | 주 1회 |
| **GAMP 5** | ISPE 공지·GAMP 뉴스 | 월 1회 |
| **EU Annex 11** | EudraLex Volume 4 | 월 1회 |
| **ISO 13485** | ISO 업데이트 공지 | 분기 1회 |

### 1.2 자동화 아키텍처

```text
[스케줄러]
   │ 매주 월요일 09:00
   ▼
[규제 소스 수집기]
   ├── FDA Guidance Search
   ├── eCFR Part 11
   ├── eCFR Part 820
   ├── ISPE GAMP News
   └── EudraLex Annex 11
   │
   ▼
[변경 감지기]
   ├── 페이지 해시 비교
   ├── 제목·발행일 추출
   └── 키워드 필터
   │
   ▼
[알림 발송기]
   ├── 이메일
   ├── Slack / Teams
   └── eQMS 알림센터
   │
   ▼
[감사추적 기록]
```

### 1.3 Python 스케줄러 예시

```python
# jobs/regulatory_monitor.py
import hashlib
import httpx
from datetime import datetime, timezone

from app.core.database import get_db
from app.core.audit import write_audit
from app.services.notifier import send_email, send_slack

SOURCES = [
    {
        "source_id": "fda_guidance",
        "url": "https://www.fda.gov/regulatory-information/search-fda-guidance-documents",
        "keywords": [
            "21 CFR Part 11",
            "electronic records",
            "electronic signatures",
            "computer software assurance",
        ],
    },
    {
        "source_id": "ecfr_part_11",
        "url": "https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11",
        "keywords": [
            "electronic records",
            "electronic signatures",
            "audit trail",
        ],
    },
    {
        "source_id": "ecfr_part_820",
        "url": "https://www.ecfr.gov/current/title-21/chapter-I/subchapter-H/part-820",
        "keywords": [
            "quality management system regulation",
            "design and development",
            "medical device file",
        ],
    },
]


async def check_regulatory_updates():
    for source in SOURCES:
        async with httpx.AsyncClient(timeout=30) as client:
            response = await client.get(source["url"])
            content = response.text

        content_hash = hashlib.sha256(content.encode()).hexdigest()

        previous_hash = await get_previous_source_hash(
            source_id=source["source_id"],
        )

        if previous_hash and previous_hash != content_hash:
            matched_keywords = [
                keyword
                for keyword in source["keywords"]
                if keyword.lower() in content.lower()
            ]

            if matched_keywords:
                await send_email(
                    subject=f"[Regulatory Update] {source['source_id']}",
                    body="\n".join(matched_keywords),
                )

                await send_slack(
                    channel="#regulatory-watch",
                    message=f"Regulatory update detected: {source['source_id']}",
                )

        await save_source_hash(
            source_id=source["source_id"],
            content_hash=content_hash,
            checked_at=datetime.now(timezone.utc),
        )
```

### 1.4 알림 감사추적

```python
await write_audit(
    db=db,
    object_type="regulatory_monitor",
    object_id=source["source_id"],
    action="READ",
    before_state={"previous_hash": previous_hash},
    after_state={
        "current_hash": content_hash,
        "matched_keywords": matched_keywords,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    },
    actor_id="system",
    request=request,
    reason="Scheduled regulatory guidance monitoring",
)
```

FDA는 공식 Guidance Documents 검색 페이지를 통해 최신 가이던스를 확인할 수 있도록 하고 있으며, 이 페이지를 모니터링 대상으로 사용하는 것이 적절합니다. [fda](https://www.fda.gov/regulatory-information/search-fda-guidance-documents)

***

## ② CAPA 관리 DB 스키마와 트리거

### 2.1 CAPA 프로세스

```text
[Nonconformance 발생]
        │
        ▼
[NC 등록]
        │
        ▼
[CAPA 생성]
        │
        ▼
[원인분석]
        │
        ▼
[시정조치 / 예방조치 계획]
        │
        ▼
[조치 실행]
        │
        ▼
[효과성 확인]
        │
        ▼
[CAPA 종결]
```

### 2.2 CAPA 스키마

```sql
-- 1. 부적합 관리
CREATE TABLE nonconformances (
    nc_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nc_no            VARCHAR(30) UNIQUE NOT NULL,
    title            VARCHAR(200) NOT NULL,
    description      TEXT NOT NULL,
    source_type      VARCHAR(30) NOT NULL
                     CHECK (source_type IN (
                         'INTERNAL_AUDIT','CUSTOMER_COMPLAINT',
                         'PRODUCTION','SUPPLIER','REGULATORY','OTHER'
                     )),
    source_reference VARCHAR(100),
    detected_at      DATE NOT NULL,
    severity         VARCHAR(20) NOT NULL
                     CHECK (severity IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    status           VARCHAR(30) NOT NULL DEFAULT 'OPEN'
                     CHECK (status IN (
                         'OPEN','UNDER_INVESTIGATION',
                         'CAPA_CREATED','CLOSED'
                     )),
    owner_id         UUID NOT NULL REFERENCES users(user_id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. CAPA 관리
CREATE TABLE capa_records (
    capa_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capa_no             VARCHAR(30) UNIQUE NOT NULL,
    nc_id               UUID REFERENCES nonconformances(nc_id),
    title               VARCHAR(200) NOT NULL,
    problem_statement   TEXT NOT NULL,
    root_cause          TEXT,
    root_cause_method   VARCHAR(50)
                        CHECK (root_cause_method IN (
                            '5WHY','FISHBONE','FMEA','FTA','OTHER'
                        )),
    corrective_action   TEXT,
    preventive_action   TEXT,
    action_owner_id     UUID REFERENCES users(user_id),
    due_date            DATE,
    effectiveness_check TEXT,
    effectiveness_due   DATE,
    status              VARCHAR(30) NOT NULL DEFAULT 'OPEN'
                        CHECK (status IN (
                            'OPEN','ROOT_CAUSE_ANALYSIS',
                            'ACTION_PLANNED','ACTION_IN_PROGRESS',
                            'EFFECTIVENESS_CHECK','CLOSED'
                        )),
    created_by          UUID NOT NULL REFERENCES users(user_id),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. CAPA 조치 이력
CREATE TABLE capa_actions (
    action_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capa_id         UUID NOT NULL REFERENCES capa_records(capa_id),
    action_type     VARCHAR(30) NOT NULL
                    CHECK (action_type IN (
                        'CORRECTIVE','PREVENTIVE','EFFECTIVENESS_CHECK'
                    )),
    description     TEXT NOT NULL,
    owner_id        UUID NOT NULL REFERENCES users(user_id),
    due_date        DATE,
    completed_at    TIMESTAMPTZ,
    result          TEXT,
    status          VARCHAR(30) NOT NULL DEFAULT 'PLANNED'
                    CHECK (status IN (
                        'PLANNED','IN_PROGRESS','COMPLETED','VERIFIED'
                    )),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. CAPA 문서 연계
CREATE TABLE capa_documents (
    link_id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capa_id              UUID NOT NULL REFERENCES capa_records(capa_id),
    document_version_id  UUID NOT NULL REFERENCES document_versions(id),
    link_type            VARCHAR(30) NOT NULL
                         CHECK (link_type IN (
                             'INVESTIGATION','ACTION_PLAN',
                             'EVIDENCE','EFFECTIVENESS_REPORT'
                         )),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 2.3 CAPA 감사 트리거

```sql
CREATE OR REPLACE FUNCTION fn_audit_capa_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    v_event_uuid := fn_insert_audit_event(
        p_object_type => 'capa_record',
        p_object_id => COALESCE(NEW.capa_id, OLD.capa_id),
        p_action => TG_OP,
        p_before => CASE
            WHEN TG_OP = 'INSERT' THEN NULL
            ELSE to_jsonb(OLD)
        END,
        p_after => CASE
            WHEN TG_OP = 'DELETE' THEN NULL
            ELSE to_jsonb(NEW)
        END,
        p_reason => 'Database-level CAPA change'
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_capa_records_audit ON capa_records;

CREATE TRIGGER trg_capa_records_audit
AFTER INSERT OR UPDATE OR DELETE ON capa_records
FOR EACH ROW
EXECUTE FUNCTION fn_audit_capa_change();


CREATE OR REPLACE FUNCTION fn_audit_nc_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    v_event_uuid := fn_insert_audit_event(
        p_object_type => 'nonconformance',
        p_object_id => COALESCE(NEW.nc_id, OLD.nc_id),
        p_action => TG_OP,
        p_before => CASE
            WHEN TG_OP = 'INSERT' THEN NULL
            ELSE to_jsonb(OLD)
        END,
        p_after => CASE
            WHEN TG_OP = 'DELETE' THEN NULL
            ELSE to_jsonb(NEW)
        END,
        p_reason => 'Database-level nonconformance change'
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_nonconformances_audit ON nonconformances;

CREATE TRIGGER trg_nonconformances_audit
AFTER INSERT OR UPDATE OR DELETE ON nonconformances
FOR EACH ROW
EXECUTE FUNCTION fn_audit_nc_change();


CREATE OR REPLACE FUNCTION fn_audit_capa_action_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    v_event_uuid := fn_insert_audit_event(
        p_object_type => 'capa_action',
        p_object_id => COALESCE(NEW.action_id, OLD.action_id),
        p_action => TG_OP,
        p_before => CASE
            WHEN TG_OP = 'INSERT' THEN NULL
            ELSE to_jsonb(OLD)
        END,
        p_after => CASE
            WHEN TG_OP = 'DELETE' THEN NULL
            ELSE to_jsonb(NEW)
        END,
        p_reason => 'Database-level CAPA action change'
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_capa_actions_audit ON capa_actions;

CREATE TRIGGER trg_capa_actions_audit
AFTER INSERT OR UPDATE OR DELETE ON capa_actions
FOR EACH ROW
EXECUTE FUNCTION fn_audit_capa_action_change();
```

### 2.4 CAPA 종결 제약 트리거

```sql
CREATE OR REPLACE FUNCTION fn_validate_capa_closure()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_open_actions INT;
    v_effectiveness_action INT;
BEGIN
    IF NEW.status = 'CLOSED' THEN
        SELECT COUNT(*)
        INTO v_open_actions
        FROM capa_actions
        WHERE capa_id = NEW.capa_id
          AND status NOT IN ('COMPLETED', 'VERIFIED');

        SELECT COUNT(*)
        INTO v_effectiveness_action
        FROM capa_actions
        WHERE capa_id = NEW.capa_id
          AND action_type = 'EFFECTIVENESS_CHECK'
          AND status = 'VERIFIED';

        IF v_open_actions > 0 THEN
            RAISE EXCEPTION
                'CAPA cannot be closed: unresolved actions exist';
        END IF;

        IF v_effectiveness_action = 0 THEN
            RAISE EXCEPTION
                'CAPA cannot be closed: effectiveness check is missing';
        END IF;

        IF NEW.effectiveness_check IS NULL
        OR NEW.effectiveness_check = '' THEN
            RAISE EXCEPTION
                'CAPA cannot be closed: effectiveness result is required';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_capa_closure_validation ON capa_records;

CREATE TRIGGER trg_capa_closure_validation
BEFORE UPDATE ON capa_records
FOR EACH ROW
EXECUTE FUNCTION fn_validate_capa_closure();
```

***

## ③ 설계추적성 RTM DB 스키마와 연결 쿼리

### 3.1 RTM 구조

```text
[Regulatory Requirement]
        │
        ▼
[User Need]
        │
        ▼
[System Requirement]
        │
        ▼
[Design Specification]
        │
        ▼
[Implementation]
        │
        ▼
[Test Case]
        │
        ▼
[Test Execution]
        │
        ▼
[Validation Evidence]
```

RTM은 요구사항을 원천, 설계, 시험, 검증증적까지 양방향으로 연결하며, 요구사항 ID·설계·시험·결과·위험통제·규제 참조를 포함해야 합니다. 

### 3.2 RTM DB 스키마

```sql
-- 1. 요구사항
CREATE TABLE requirements (
    requirement_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_no VARCHAR(30) UNIQUE NOT NULL,
    requirement_type VARCHAR(30) NOT NULL
                     CHECK (requirement_type IN (
                         'REGULATORY','USER_NEED','SYSTEM',
                         'SOFTWARE','HARDWARE','PROCESS'
                     )),
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    source_document VARCHAR(200),
    source_section VARCHAR(100),
    priority VARCHAR(20) NOT NULL
              CHECK (priority IN ('HIGH','MEDIUM','LOW')),
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT'
           CHECK (status IN (
               'DRAFT','APPROVED','IMPLEMENTED',
               'VERIFIED','VALIDATED','REJECTED','RETIRED'
           )),
    owner_id UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. 설계 항목
CREATE TABLE design_items (
    design_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    design_no VARCHAR(30) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT NOT NULL,
    design_type VARCHAR(30) NOT NULL
                CHECK (design_type IN (
                    'ARCHITECTURE','DATABASE','API','UI',
                    'WORKFLOW','CONTROL','ALGORITHM'
                )),
    document_version_id UUID REFERENCES document_versions(id),
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. 시험 케이스
CREATE TABLE test_cases (
    test_case_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_case_no VARCHAR(30) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    test_type VARCHAR(30) NOT NULL
              CHECK (test_type IN (
                  'IQ','OQ','PQ','UNIT','INTEGRATION','REGRESSION'
              )),
    test_method VARCHAR(30) NOT NULL
                CHECK (test_method IN (
                    'TEST','INSPECTION','ANALYSIS','DEMONSTRATION'
                )),
    expected_result TEXT NOT NULL,
    protocol_document VARCHAR(200),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. 시험 실행 결과
CREATE TABLE test_executions (
    execution_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    test_case_id UUID NOT NULL REFERENCES test_cases(test_case_id),
    executed_by UUID NOT NULL REFERENCES users(user_id),
    executed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    result VARCHAR(30) NOT NULL
           CHECK (result IN ('PASS','FAIL','BLOCKED','NOT_EXECUTED')),
    actual_result TEXT,
    evidence_file_id UUID REFERENCES files(id),
    deviation_id UUID,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. 추적성 관계
CREATE TABLE traceability_links (
    link_id BIGSERIAL PRIMARY KEY,
    source_type VARCHAR(30) NOT NULL
                CHECK (source_type IN (
                    'REQUIREMENT','DESIGN','TEST_CASE',
                    'TEST_EXECUTION','RISK','CAPA','DOCUMENT'
                )),
    source_id UUID NOT NULL,
    target_type VARCHAR(30) NOT NULL
                CHECK (target_type IN (
                    'REQUIREMENT','DESIGN','TEST_CASE',
                    'TEST_EXECUTION','RISK','CAPA','DOCUMENT'
                )),
    target_id UUID NOT NULL,
    relation_type VARCHAR(30) NOT NULL
                  CHECK (relation_type IN (
                      'TRACES_TO','IMPLEMENTED_BY',
                      'VERIFIED_BY','VALIDATED_BY',
                      'MITIGATED_BY','DERIVES_FROM'
                  )),
    created_by UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (
        source_type, source_id,
        target_type, target_id,
        relation_type
    )
);
```

### 3.3 RTM 연결 쿼리

```sql
SELECT
    r.requirement_no AS requirement_id,
    r.title AS requirement,
    r.source_document AS regulatory_source,
    d.design_no AS design_id,
    d.title AS design_specification,
    t.test_case_no AS test_case_id,
    t.title AS test_case,
    te.result AS test_result,
    te.executed_at AS executed_at,
    te.evidence_file_id AS evidence
FROM requirements r
LEFT JOIN traceability_links l1
    ON l1.source_type = 'REQUIREMENT'
   AND l1.source_id = r.requirement_id
   AND l1.target_type = 'DESIGN'
   AND l1.relation_type = 'IMPLEMENTED_BY'
LEFT JOIN design_items d
    ON d.design_id = l1.target_id
LEFT JOIN traceability_links l2
    ON l2.source_type = 'REQUIREMENT'
   AND l2.source_id = r.requirement_id
   AND l2.target_type = 'TEST_CASE'
   AND l2.relation_type = 'VERIFIED_BY'
LEFT JOIN test_cases t
    ON t.test_case_id = l2.target_id
LEFT JOIN test_executions te
    ON te.test_case_id = t.test_case_id
ORDER BY r.requirement_no, t.test_case_no;
```

### 3.4 미커버 요구사항 리포트

```sql
SELECT
    r.requirement_no,
    r.title,
    r.priority,
    COUNT(l.link_id) AS linked_test_count
FROM requirements r
LEFT JOIN traceability_links l
    ON l.source_type = 'REQUIREMENT'
   AND l.source_id = r.requirement_id
   AND l.target_type = 'TEST_CASE'
   AND l.relation_type = 'VERIFIED_BY'
GROUP BY r.requirement_no, r.title, r.priority
HAVING COUNT(l.link_id) = 0
ORDER BY r.priority DESC, r.requirement_no;
```

***

## ④ CSV 패키지 시험 프로토콜 및 VSR 템플릿

### 4.1 CSV 패키지 구성

| 문서 | 목적 |
|---|---|
| **VMP** | 검증 전략·범위·역할 정의 |
| **URS** | 사용자·규제 요구사항 정의 |
| **Risk Assessment** | 기능별 위험·통제 정의 |
| **RTM** | URS-위험-설계-시험 연결 |
| **IQ Protocol** | 설치·환경·구성 검증 |
| **OQ Protocol** | 기능·경계·오류조건 검증 |
| **PQ Protocol** | 실제 업무 시나리오 검증 |
| **Test Evidence** | 실행결과·스크린샷·로그 |
| **Deviation Log** | 편차·원인·조치·재시험 |
| **VSR** | 검증요약·잔여리스크·운영승인 |
| **SOP** | 운영·백업·장애·변경절차 |
| **Training Record** | 사용자 교육·이수 증적 |

검증 프로토콜은 목적, 범위, 위험관리 접근, 명세, 수용기준, 시험, 교육, 시스템 릴리스를 포함해야 하며, 검증보고서는 프로토콜 결과와 편차를 요약하고 결론을 제시해야 합니다. [manageengine](https://www.manageengine.com/za/compliance-manager/gamp-5-compliance/)

### 4.2 IQ 프로토콜 템플릿

```markdown
# Installation Qualification (IQ)

## IQ-001: 서버 및 OS 확인
- URS: URS-INF-001
- 시험방법: 서버 사양 및 OS 버전 확인
- 기대결과: 승인 사양과 일치
- 실제결과:
- 판정: Pass / Fail
- 증적:

## IQ-002: PostgreSQL 설치 확인
- URS: URS-INF-002
- 시험방법: `SELECT version();`
- 기대결과: PostgreSQL 16 이상
- 실제결과:
- 판정: Pass / Fail

## IQ-003: 감사추적 테이블 확인
- URS: URS-AT-001
- 시험방법: `audit_events` 테이블·인덱스·트리거 확인
- 기대결과: 모든 객체 존재
- 실제결과:
- 판정: Pass / Fail

## IQ-004: MinIO WORM 설정 확인
- URS: URS-STG-001
- 시험방법: 버킷 정책 및 버전관리 확인
- 기대결과: 원본 덮어쓰기 방지
- 실제결과:
- 판정: Pass / Fail

## IQ-005: DSS 서비스 접속 확인
- URS: URS-SIG-001
- 시험방법: DSS REST 헬스체크
- 기대결과: HTTP 200
- 실제결과:
- 판정: Pass / Fail
```

### 4.3 OQ 프로토콜 템플릿

```markdown
# Operational Qualification (OQ)

## OQ-DOC-001: 문서 등록
- URS: URS-DC-001
- 사전조건: QA_ADMIN 계정 로그인
- 시험절차:
  1. SOP 문서 등록
  2. 문서번호 자동 생성 확인
  3. SHA-256 해시 생성 확인
- 기대결과: 문서 생성 및 감사기록 1건 생성
- 실제결과:
- 판정: Pass / Fail
- 증적:

## OQ-AT-001: 감사추적 생성
- URS: URS-AT-001
- 시험절차:
  1. 문서 생성
  2. 문서 수정
  3. 감사기록 조회
- 기대결과: CREATE, UPDATE 기록 존재
- 실제결과:
- 판정: Pass / Fail

## OQ-AT-002: 감사추적 변경 차단
- URS: URS-AT-002
- 시험절차:
  1. `UPDATE audit_events` 실행
  2. `DELETE FROM audit_events` 실행
- 기대결과: 두 작업 모두 차단
- 실제결과:
- 판정: Pass / Fail

## OQ-SIG-001: PAdES 전자서명
- URS: URS-SIG-001
- 시험절차:
  1. 승인자 로그인
  2. SOP PDF 서명 요청
  3. DSS 검증 요청
- 기대결과: 서명 성공 및 검증 성공
- 실제결과:
- 판정: Pass / Fail

## OQ-CAPA-003: CAPA 종결 제약
- URS: URS-CAPA-003
- 시험절차:
  1. 미완료 조치 상태에서 CAPA 종결 시도
  2. 효과성 확인 누락 상태에서 종결 시도
- 기대결과: 두 경우 모두 차단
- 실제결과:
- 판정: Pass / Fail

## OQ-RAG-001: 승인 문서만 검색
- URS: URS-RAG-001
- 시험절차:
  1. DRAFT 문서 업로드
  2. APPROVED 문서 업로드
  3. RAG 질의 실행
- 기대결과: APPROVED 문서만 검색
- 실제결과:
- 판정: Pass / Fail
```

### 4.4 PQ 프로토콜 템플릿

```markdown
# Performance Qualification (PQ)

## PQ-001: SOP 개정 전 과정
- 참여자: 문서작성자, 검토자, 승인자, 품질관리자
- 시나리오:
  1. SOP v1.0 등록
  2. 검토자 검토
  3. 승인자 PAdES 서명
  4. 유효일 설정 및 배포
  5. RAG에서 v1.0 검색
  6. v2.0 신규 버전 생성
  7. v1.0 SUPERSEDED 처리
- 수용기준:
  - 모든 상태 전이 기록
  - 모든 서명 기록
  - 감사추적 완전성 확인
  - RAG가 승인 문서만 검색

## PQ-002: CAPA 문서 연계
- 시나리오:
  1. Odoo에서 CAPA 생성
  2. FastAPI로 시정조치 문서 등록
  3. Nextcloud 원본 저장
  4. 승인 및 서명
  5. 감사추적 확인
- 수용기준:
  - CAPA ID와 문서 ID 연결
  - 원본·서명본 구분 저장
  - 감사기록 완전성 확인

## PQ-003: RAG 품질담당자 사용성 평가
- 참여자: 품질담당자 3~5명
- 평가 문항: 문서당 5~10개
- 평가 항목:
  - 정확성
  - 출처일치
  - 완결성
  - 환각률
  - 검색 재현율 Hit@5
- 수용기준:
  - 정확성 80% 이상
  - 환각률 10% 미만
  - 출처 문서·버전 표시 100%

## PQ-004: 백업 및 복구
- 시나리오:
  1. PostgreSQL 백업
  2. MinIO/Nextcloud 원본 백업
  3. 장애 시뮬레이션
  4. 복구 실행
- 수용기준:
  - DB 복구 성공
  - 문서 원본 복구 성공
  - 감사추적 연속성 확인
```

### 4.5 Validation Summary Report(VSR) 템플릿

```markdown
# Validation Summary Report (VSR)

## 1. 문서 정보
- 문서번호: VSR-EQMS-001
- 버전: 1.0
- 시스템명: Medical eQMS
- 검증기간:
- 작성자:
- 승인자:

## 2. 검증 범위
- 문서관리
- 버전관리
- 감사추적
- 전자서명
- CAPA
- 교육
- 설계추적성
- RAG 검색

## 3. 검증 결과 요약
| 문서 | 총 테스트 | 통과 | 실패 | 편차 | 판정 |
|---|---:|---:|---:|---:|---|
| IQ |  |  |  |  |  |
| OQ |  |  |  |  |  |
| PQ |  |  |  |  |  |

## 4. 편차 요약
| 편차번호 | 내용 | 원인 | 영향 | 조치 | 재시험결과 | 종결여부 |
|---|---|---|---|---|---|---|

## 5. 잔여리스크
| Risk ID | 내용 | 완화책 | 수용여부 |
|---|---|---|---|

## 6. 추적성 확인
- 모든 URS가 실행된 시험과 연결됨
- 모든 실행된 시험이 URS로 추적됨
- RTM 완전성 확인

## 7. 결론 및 릴리스 판정
- Validated / Validated with restrictions / Not validated
- 운영 전환 가능 여부
- 조건부 승인 시 조건 명시

## 8. 운영 전환 승인
- QA Owner 승인:
- System Owner 승인:
- 승인일:
- 운영 전환일:
```

VSR은 시스템·범위, 프로토콜·수용기준, 결과, 편차, 미해결 항목, 추적성 확인, 릴리스 판정, 승인자 서명을 포함해야 하며, 조건부 승인도 문서화된 위험 평가를 전제로 허용됩니다. [casrai](https://casrai.org/guides/validation-summary-report)

***

## ⑤ FastAPI 감사추적 미들웨어와 컨텍스트 연동

### 5.1 요청 컨텍스트 미들웨어

```python
# app/core/middleware.py
import time
import uuid

from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware


class AuditContextMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        request_id = str(uuid.uuid4())
        start_time = time.time()

        request.state.request_id = request_id
        request.state.audit_context = {
            "request_id": request_id,
            "method": request.method,
            "path": request.url.path,
            "client_ip": request.client.host if request.client else None,
            "user_agent": request.headers.get("user-agent"),
        }

        response = await call_next(request)

        elapsed_ms = round((time.time() - start_time) * 1000, 2)

        request.state.audit_context.update(
            {
                "status_code": response.status_code,
                "elapsed_ms": elapsed_ms,
            }
        )

        response.headers["X-Request-ID"] = request_id

        return response
```

### 5.2 감사추적 서비스

```python
# app/core/audit.py
import hashlib
import json
from datetime import datetime, timezone

from fastapi import Request
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

SENSITIVE_KEYS = {
    "password",
    "token",
    "secret",
    "pin",
    "private_key",
    "keystore_password",
}


def sanitize(state: dict | None) -> dict | None:
    if state is None:
        return None

    return {
        key: ("***" if key.lower() in SENSITIVE_KEYS else value)
        for key, value in state.items()
    }


def make_hash(payload: dict) -> str:
    canonical = json.dumps(
        payload,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


async def get_last_hash(
    db: AsyncSession,
    object_type: str,
    object_id: str,
) -> str | None:
    result = await db.execute(
        text("""
            SELECT record_hash
            FROM audit_events
            WHERE object_type = :object_type
              AND object_id = CAST(:object_id AS UUID)
            ORDER BY occurred_at DESC, audit_id DESC
            LIMIT 1
        """),
        {
            "object_type": object_type,
            "object_id": object_id,
        },
    )

    row = result.first()
    return row.record_hash if row else None


async def write_audit(
    db: AsyncSession,
    *,
    object_type: str,
    object_id: str,
    action: str,
    before_state: dict | None,
    after_state: dict | None,
    actor_id: str,
    request: Request,
    reason: str | None = None,
) -> str:
    prev_hash = await get_last_hash(db, object_type, object_id)

    occurred_at = datetime.now(timezone.utc).isoformat()

    payload = {
        "object_type": object_type,
        "object_id": object_id,
        "action": action,
        "before_state": sanitize(before_state),
        "after_state": sanitize(after_state),
        "actor_id": actor_id,
        "actor_ip": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
        "request_id": getattr(request.state, "request_id", None),
        "reason": reason,
        "occurred_at": occurred_at,
        "prev_hash": prev_hash,
    }

    record_hash = make_hash(payload)

    result = await db.execute(
        text("""
            INSERT INTO audit_events (
                event_uuid,
                object_type,
                object_id,
                action,
                before_state,
                after_state,
                actor_id,
                actor_ip,
                user_agent,
                reason,
                occurred_at,
                prev_hash,
                record_hash
            )
            VALUES (
                gen_random_uuid(),
                :object_type,
                CAST(:object_id AS UUID),
                :action,
                CAST(:before_state AS JSONB),
                CAST(:after_state AS JSONB),
                CAST(:actor_id AS UUID),
                :actor_ip,
                :user_agent,
                :reason,
                :occurred_at,
                :prev_hash,
                :record_hash
            )
            RETURNING event_uuid
        """),
        {
            **payload,
            "before_state": json.dumps(
                payload["before_state"],
                ensure_ascii=False,
            ),
            "after_state": json.dumps(
                payload["after_state"],
                ensure_ascii=False,
            ),
        },
    )

    await db.commit()
    return str(result.scalar_one())
```

### 5.3 CAPA 생성 API 적용

```python
# app/routers/capa.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/api/capa")


class CapaCreateRequest(BaseModel):
    nc_id: str
    title: str
    problem_statement: str
    root_cause: str | None = None
    corrective_action: str | None = None
    preventive_action: str | None = None
    due_date: str | None = None


@router.post("")
async def create_capa(
    body: CapaCreateRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_ADMIN", "QA_ENGINEER"}:
        raise HTTPException(status_code=403, detail="Not authorized")

    capa_id = await insert_capa(
        db=db,
        nc_id=body.nc_id,
        title=body.title,
        problem_statement=body.problem_statement,
        root_cause=body.root_cause,
        corrective_action=body.corrective_action,
        preventive_action=body.preventive_action,
        due_date=body.due_date,
        created_by=current_user.user_id,
    )

    after_state = {
        "nc_id": body.nc_id,
        "title": body.title,
        "status": "OPEN",
        "owner_id": current_user.user_id,
    }

    await write_audit(
        db=db,
        object_type="capa_record",
        object_id=capa_id,
        action="CREATE",
        before_state=None,
        after_state=after_state,
        actor_id=current_user.user_id,
        request=request,
        reason="CAPA creation from nonconformance",
    )

    return {
        "capa_id": capa_id,
        "status": "OPEN",
    }
```

### 5.4 앱 등록

```python
# app/main.py
from fastapi import FastAPI

from app.core.middleware import AuditContextMiddleware
from app.routers import audit, capa, documents, signature

app = FastAPI(
    title="Medical eQMS",
    version="0.3.0",
)

app.add_middleware(AuditContextMiddleware)

app.include_router(documents.router)
app.include_router(signature.router)
app.include_router(capa.router)
app.include_router(audit.router)
```

감사 로그는 actor, action, resource, timestamp, outcome을 포함하는 구조화된 이벤트로 설계하고, append-only 저장과 해시 체인으로 변조 탐지성을 확보하는 것이 권장됩니다. 

***

## ⑥ 운영 및 검증 완료 기준

| 영역 | 완료 기준 |
|---|---|
| **CAPA** | NC-CAPA-조치-효과성 확인까지 추적 |
| **교육** | 문서 승인 시 자동 할당, 이수기록 append-only |
| **RTM** | URS-설계-시험-증적 양방향 연결 |
| **CSV** | VMP-URS-Risk-RTM-IQ/OQ/PQ-VSR 연결 |
| **감사추적** | DB 트리거 + FastAPI 이중 기록 |
| **전자서명** | PAdES 서명·검증·변조 탐지 |
| **RAG** | 승인 문서만 검색, 출처·버전 인용 |
| **규제 모니터링** | FDA·GAMP·Annex 11 변경 자동 감지 및 알림 |

이 구조로 완성하면 **CAPA는 NC와 효과성 확인까지 추적**, **교육은 문서 승인과 자동 연계**, **RTM은 URS-설계-시험-증적까지 연결**, **CSV는 VMP부터 VSR까지 일관된 증적 체계**로 운영되는 규제 준수형 eQMS가 됩니다. [manageengine](https://www.manageengine.com/za/compliance-manager/gamp-5-compliance/)