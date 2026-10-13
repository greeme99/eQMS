아래는 **CAPA, 교육, RTM, CSV, 감사추적, 전자서명**을 하나의 규제 준수형 eQMS로 완성하기 위한 개발 가이드입니다. 핵심은 **DB 트리거로 데이터 변경 자체를 기록**하고, **FastAPI 미들웨어로 사용자·요청 맥락을 보강**하며, **DSS PAdES 서명과 감사추적을 연동**하는 이중 통제 구조입니다. PostgreSQL 감사 로그는 append-only 설계와 해시 체인으로 변조 탐지성을 확보하는 것이 권장됩니다. [intelligentgraphicandcode](https://www.intelligentgraphicandcode.com/development/audit-trails)

***

## ① 전체 시스템 구조

```text
[사용자]
   │ HTTPS
   ▼
[FastAPI eQMS]
   │
   ├── [AuditContextMiddleware] ── 요청 ID·IP·UA·처리시간
   ├── [Audit Service] ── 사용자·행위·사유·해시체인
   ├── [DSS PAdES Service] ── PDF 전자서명·검증
   ├── [PostgreSQL] ── 문서·CAPA·교육·RTM·감사추적
   ├── [MinIO/Nextcloud] ── 원본 PDF·서명 PDF
   └── [Haystack + Qdrant] ── 승인 SOP RAG
```

CAPA는 NC에서 시작해 효과성 확인까지 추적하고, 교육은 문서 승인 시 자동 할당되며, RTM은 URS-설계-시험-증적을 연결하고, CSV는 VMP부터 VSR까지 증적 체계를 유지합니다. VMP는 검증 전략·범위·역할·위험 접근을 정의하고, URS는 각 요구사항이 시험 가능하도록 번호를 부여해 추적성 매트릭스와 연결해야 합니다. [pharmadevils](https://pharmadevils.com/wp-content/uploads/2025/01/Computer-System-Validation-Master-Plan.pdf)

***

## ② CSV VMP 및 URS 검증 템플릿

### 2.1 Validation Master Plan(VMP)

```markdown
# Validation Master Plan (VMP)

## 1. 문서 정보
- 문서번호: VMP-EQMS-001
- 버전: 1.0
- 시스템명: Medical eQMS
- 작성자:
- 검토자:
- 승인자:
- 승인일:

## 2. 목적
본 계획은 Medical eQMS가 승인된 URS, 위험통제 기준 및 규제 요구를
충족함을 검증하기 위한 전략, 범위, 역할, 수용기준을 정의한다.

## 3. 시스템 개요
- 시스템명: Medical eQMS
- 목적: 의료기기 제조 품질·GMP 기록의 전산화 및 규제 준수
- 주요 모듈:
  - 문서관리
  - 감사추적
  - PAdES 전자서명
  - CAPA
  - 교육·이수관리
  - 설계추적성
  - 승인 SOP RAG 검색
- 배포형태: On-Premise
- GAMP 분류: Category 4 또는 Category 5

## 4. 검증 범위
### 포함
- 문서등록 및 버전관리
- 승인 워크플로
- 감사추적
- PAdES 전자서명
- CAPA
- 교육·이수관리
- 설계추적성
- 승인 SOP RAG 검색

### 제외
- ERP 재무연동
- 외부 협력사 포털
- 생산설비 제어 시스템

## 5. 규제 요구
- FDA 21 CFR Part 11
- FDA QMSR / ISO 13485
- EU Annex 11
- GAMP 5

## 6. 역할 및 책임
| 역할 | 책임 |
|---|---|
| QA Owner | URS 승인, 검증결과 승인 |
| System Owner | 운영환경 승인 |
| IT Validation | IQ/OQ 실행 |
| Business User | PQ 실행 |
| Auditor | 검증증적 검토 |

## 7. 검증 전략
- 위험 기반 검증
- 개발/검증/운영 환경 분리
- URS-위험-설계-시험 추적성 유지
- 감사추적·전자서명 우선 검증
- 변경 발생 시 영향평가 및 재검증

## 8. 수용기준
- High Risk 테스트 100% 통과
- 모든 URS에 대응 테스트 존재
- 편차 없음 또는 승인된 편차만 존재
- 감사추적 증적 완전성 확보
```

VMP는 시스템 범위, 목표, 역할, 위험 접근, 일정, 검증 산출물을 정의하는 상위 검증계획 문서입니다. [pharmadevils](https://pharmadevils.com/wp-content/uploads/2025/01/Computer-System-Validation-Master-Plan.pdf)

### 2.2 URS 템플릿

```markdown
# User Requirements Specification (URS)

## 1. 문서 정보
- 문서번호: URS-EQMS-001
- 버전: 1.0
- 작성자:
- 검토자:
- 승인자:
- 승인일:

## 2. 요구사항 분류
- FR: Functional Requirement
- NFR: Non-Functional Requirement
- CR: Compliance Requirement
- SR: Security Requirement

## 3. 문서관리 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-DC-001 | FR | 사용자는 SOP를 등록할 수 있다 | 문서번호·제목·유형·소유자 저장 | High | OQ |
| URS-DC-002 | FR | 사용자는 신규 버전을 생성할 수 있다 | 구버전은 SUPERSEDED 처리 | High | OQ |
| URS-DC-003 | FR | 문서는 승인 후 배포된다 | 승인 전 배포 불가 | High | OQ |

## 4. 감사추적 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-AT-001 | CR | 생성·수정·승인 행위는 감사추적된다 | 감사기록 생성 | High | OQ |
| URS-AT-002 | CR | 감사기록은 수정·삭제될 수 없다 | UPDATE/DELETE 차단 | High | OQ |
| URS-AT-003 | CR | 감사기록은 사용자·시각·사유를 포함한다 | 필수 필드 존재 | High | OQ |

## 5. 전자서명 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-SIG-001 | CR | 승인자는 PAdES 전자서명을 수행한다 | 서명 성공 및 검증 성공 | High | OQ |
| URS-SIG-002 | CR | 서명 후 원문 변경은 탐지된다 | 변조 시 검증 실패 | High | OQ |
| URS-SIG-003 | CR | 서명자·시각·서명의미는 기록된다 | 서명 메타데이터 저장 | High | OQ |

## 6. CAPA 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-CAPA-001 | FR | NC를 등록할 수 있다 | NC번호·심각도·소유자 저장 | High | OQ |
| URS-CAPA-002 | FR | NC에서 CAPA를 생성할 수 있다 | NC-CAPA 연결 | High | OQ |
| URS-CAPA-003 | CR | CAPA 종결 시 효과성 확인이 필요하다 | 미완료 조치 시 종결 차단 | High | OQ |

## 7. 교육 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-TRN-001 | FR | 문서 승인 시 교육을 할당한다 | 대상자별 교육기록 생성 | Medium | OQ |
| URS-TRN-002 | FR | 교육 이수 여부를 관리한다 | 이수일·평가·상태 저장 | Medium | OQ |
| URS-TRN-003 | CR | 교육기록은 변경·삭제될 수 없다 | append-only 기록 | High | OQ |

## 8. 설계추적성 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-RTM-001 | FR | 요구사항을 설계·시험과 연결한다 | RTM 관계 저장 | High | OQ |
| URS-RTM-002 | FR | 요구사항-시험 커버리지를 확인한다 | 미커버 요구사항 리포트 | High | OQ |

## 9. RAG 요구사항

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-RAG-001 | FR | 사용자는 승인 SOP를 검색할 수 있다 | 승인 문서만 검색 | Medium | OQ |
| URS-RAG-002 | FR | 근거 없는 질문에는 근거 없음을 응답한다 | 환각 방지 응답 | Medium | OQ |
| URS-RAG-003 | CR | 검색 질의와 출처는 감사추적된다 | 질의·문서·응답 기록 | High | OQ |
```

URS의 각 요구사항은 고유 ID를 부여하고, 기능·성능·보안·데이터처리 요구를 시험 가능한 형태로 정의해야 합니다. [intuitionlabs](https://intuitionlabs.ai/pdfs/computer-system-validation-in-pharma-gamp-5-implementation.pdf)

***

## ③ 교육 관리 DB 스키마와 트리거

### 3.1 교육 프로세스

```text
[문서 승인]
     │
     ▼
[교육과정 버전 연결]
     │
     ▼
[대상 역할 자동 할당]
     │
     ▼
[교육 이수]
     │
     ▼
[평가·인증서 발급]
     │
     ▼
[감사추적 기록]
```

### 3.2 교육 스키마

```sql
-- 1. 교육과정
CREATE TABLE training_courses (
    course_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_no VARCHAR(30) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    course_type VARCHAR(30) NOT NULL
                CHECK (course_type IN (
                    'SOP','GMP','SAFETY','REGULATORY','ONBOARDING'
                )),
    target_roles TEXT[] NOT NULL,
    validity_months INT,
    is_mandatory BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. 교육과정 버전
CREATE TABLE training_course_versions (
    course_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id UUID NOT NULL REFERENCES training_courses(course_id),
    version_no VARCHAR(20) NOT NULL,
    document_version_id UUID REFERENCES document_versions(id),
    effective_date DATE,
    expiry_date DATE,
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT'
            CHECK (status IN (
                'DRAFT','APPROVED','EFFECTIVE','SUPERSEDED'
            )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (course_id, version_no)
);

-- 3. 교육 할당
CREATE TABLE training_assignments (
    assignment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_version_id UUID NOT NULL REFERENCES training_course_versions(course_version_id),
    trainee_id UUID NOT NULL REFERENCES users(user_id),
    assigned_by UUID NOT NULL REFERENCES users(user_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_date DATE NOT NULL,
    status VARCHAR(30) NOT NULL DEFAULT 'ASSIGNED'
            CHECK (status IN (
                'ASSIGNED','IN_PROGRESS','COMPLETED','OVERDUE','CANCELLED'
            ))
);

-- 4. 교육 이수기록
CREATE TABLE training_completions (
    completion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES training_assignments(assignment_id),
    trainee_id UUID NOT NULL REFERENCES users(user_id),
    course_version_id UUID NOT NULL REFERENCES training_course_versions(course_version_id),
    completed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    assessment_score NUMERIC(5,2),
    pass_fail VARCHAR(10) NOT NULL
              CHECK (pass_fail IN ('PASS','FAIL')),
    certificate_no VARCHAR(30) UNIQUE,
    expires_at DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. 교육 감사 로그
CREATE TABLE training_audit_events (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_uuid UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type VARCHAR(30) NOT NULL,
    object_id UUID NOT NULL,
    action VARCHAR(30) NOT NULL,
    before_state JSONB,
    after_state JSONB,
    actor_id UUID,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    record_hash CHAR(64) NOT NULL
);

-- 6. 교육 감사기록 불변성
CREATE OR REPLACE FUNCTION reject_training_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'training_audit_events is append-only: % is not permitted', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_training_audit_no_mutation ON training_audit_events;

CREATE TRIGGER trg_training_audit_no_mutation
BEFORE UPDATE OR DELETE ON training_audit_events
FOR EACH ROW
EXECUTE FUNCTION reject_training_audit_mutation();
```

### 3.3 문서 승인 시 교육 자동할당 트리거

```sql
CREATE OR REPLACE FUNCTION fn_assign_training_on_document_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_course_id UUID;
    v_course_version_id UUID;
    v_trainee RECORD;
BEGIN
    IF NEW.status = 'APPROVED' THEN
        SELECT course_id
        INTO v_course_id
        FROM training_course_versions
        WHERE document_version_id = NEW.version_id
        LIMIT 1;

        IF v_course_id IS NOT NULL THEN
            SELECT course_version_id
            INTO v_course_version_id
            FROM training_course_versions
            WHERE course_id = v_course_id
              AND document_version_id = NEW.version_id
            LIMIT 1;

            FOR v_trainee IN
                SELECT user_id
                FROM users
                WHERE role = ANY (
                    SELECT unnest(target_roles)
                    FROM training_courses
                    WHERE course_id = v_course_id
                )
                AND is_active = TRUE
            LOOP
                INSERT INTO training_assignments (
                    course_version_id,
                    trainee_id,
                    assigned_by,
                    due_date
                )
                VALUES (
                    v_course_version_id,
                    v_trainee.user_id,
                    NEW.created_by,
                    CURRENT_DATE + INTERVAL '14 days'
                )
                ON CONFLICT DO NOTHING;
            END LOOP;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_training_on_approval ON document_versions;

CREATE TRIGGER trg_assign_training_on_approval
AFTER UPDATE ON document_versions
FOR EACH ROW
EXECUTE FUNCTION fn_assign_training_on_document_approval();
```

### 3.4 교육 이수 감사 트리거

```sql
CREATE OR REPLACE FUNCTION fn_audit_training_completion()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_payload JSONB;
    v_hash CHAR(64);
    v_prev_hash CHAR(64);
BEGIN
    SELECT record_hash
    INTO v_prev_hash
    FROM training_audit_events
    WHERE object_type = 'training_completion'
      AND object_id = NEW.completion_id
    ORDER BY occurred_at DESC, audit_id DESC
    LIMIT 1;

    v_payload := jsonb_build_object(
        'object_type', 'training_completion',
        'object_id', NEW.completion_id,
        'action', 'CREATE',
        'after_state', to_jsonb(NEW),
        'occurred_at', clock_timestamp(),
        'prev_hash', v_prev_hash
    );

    v_hash := encode(
        digest(v_payload::text, 'sha256'),
        'hex'
    );

    INSERT INTO training_audit_events (
        object_type,
        object_id,
        action,
        before_state,
        after_state,
        actor_id,
        occurred_at,
        record_hash
    )
    VALUES (
        'training_completion',
        NEW.completion_id,
        'CREATE',
        NULL,
        to_jsonb(NEW),
        NEW.trainee_id,
        clock_timestamp(),
        v_hash
    );

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_training_completion_audit ON training_completions;

CREATE TRIGGER trg_training_completion_audit
AFTER INSERT ON training_completions
FOR EACH ROW
EXECUTE FUNCTION fn_audit_training_completion();
```

교육 시스템은 학습자, 과정, 등록, 진행, 평가, 이수, 감사기록을 분리해 관리하는 구조가 권장됩니다. 

***

## ④ 설계추적성 RTM 데이터 모델

### 4.1 RTM 구조

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

### 4.2 RTM DB 스키마

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

### 4.3 RTM 조회 쿼리

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

### 4.4 미커버 요구사항 리포트

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

## ⑤ FastAPI 감사추적 미들웨어 구현

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
    version="0.2.0",
)

app.add_middleware(AuditContextMiddleware)

app.include_router(documents.router)
app.include_router(signature.router)
app.include_router(capa.router)
app.include_router(audit.router)
```

감사 로그는 actor, action, resource, timestamp, outcome을 포함하는 구조화된 이벤트로 설계하고, append-only 저장과 해시 체인으로 변조 탐지성을 확보하는 것이 권장됩니다. [jsonic](https://jsonic.io/guides/json-audit-logging)

***

## ⑥ DSS PAdES 전자서명 파이썬 코드

### 6.1 DSS 서비스 구성

DSS는 REST WebService로 PDF 서명 생성, 서명값 결합, 문서 검증 기능을 제공하며, PAdES 서명 생성·확장·검증을 지원합니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/apidocs/eu/europa/esig/dss/pades/signature/PAdESExtensionService.html)

```yaml
# docker-compose.dss.yml
services:
  dss:
    image: esig/dss-demonstrations
    container_name: dss-service
    ports:
      - "8080:8080"
    environment:
      JAVA_OPTS: "-Xmx2g"
    restart: unless-stopped
```

### 6.2 DSS 클라이언트

```python
# app/services/dss_client.py
import httpx
from fastapi import HTTPException

DSS_BASE_URL = "http://dss-service:8080"


async def sign_pdf_with_pades(
    *,
    pdf_bytes: bytes,
    certificate_alias: str,
    keystore_password: str,
    signature_meaning: str,
) -> bytes:
    """
    DSS REST API를 호출해 PDF에 PAdES 전자서명을 생성한다.
    """
    files = {
        "document": ("document.pdf", pdf_bytes, "application/pdf"),
    }

    data = {
        "signatureForm": "PAdES",
        "packaging": "ENVELOPED",
        "digestAlgorithm": "SHA256",
        "keyAlias": certificate_alias,
        "keystorePassword": keystore_password,
        "signatureMeaning": signature_meaning,
    }

    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.post(
            f"{DSS_BASE_URL}/services/rest/signature/one-document/signDocument",
            files=files,
            data=data,
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"DSS signing failed: {response.text}",
        )

    return response.content


async def validate_signed_pdf(pdf_bytes: bytes) -> dict:
    """
    서명된 PDF의 전자서명 유효성을 검증한다.
    """
    files = {
        "document": ("signed_document.pdf", pdf_bytes, "application/pdf"),
    }

    async with httpx.AsyncClient(timeout=120) as client:
        response = await client.post(
            f"{DSS_BASE_URL}/services/rest/validation/validateDocument",
            files=files,
        )

    if response.status_code != 200:
        raise HTTPException(
            status_code=502,
            detail=f"DSS validation failed: {response.text}",
        )

    return response.json()
```

### 6.3 전자서명 라우터

```python
# app/routers/signature.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user
from app.services.dss_client import sign_pdf_with_pades, validate_signed_pdf

router = APIRouter(prefix="/api/signatures")


class PadesSignRequest(BaseModel):
    document_version_id: str
    signature_meaning: str  # REVIEW | APPROVAL | RESPONSIBILITY
    reason: str


@router.post("/pades")
async def sign_document_with_pades(
    body: PadesSignRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_REVIEWER", "QA_APPROVER"}:
        raise HTTPException(status_code=403, detail="Signing role required")

    if body.signature_meaning not in {
        "REVIEW",
        "APPROVAL",
        "RESPONSIBILITY",
    }:
        raise HTTPException(status_code=400, detail="Invalid signature meaning")

    before_state = await get_document_version_state(
        db=db,
        document_version_id=body.document_version_id,
    )

    pdf_bytes = await get_document_pdf(
        db=db,
        document_version_id=body.document_version_id,
    )

    signed_pdf = await sign_pdf_with_pades(
        pdf_bytes=pdf_bytes,
        certificate_alias=current_user.certificate_alias,
        keystore_password=current_user.keystore_password,
        signature_meaning=body.signature_meaning,
    )

    validation_result = await validate_signed_pdf(signed_pdf)

    if not validation_result.get("valid", False):
        raise HTTPException(status_code=400, detail="Signature validation failed")

    await save_signed_pdf(
        db=db,
        document_version_id=body.document_version_id,
        pdf_bytes=signed_pdf,
    )

    after_state = {
        "signed": True,
        "signature_meaning": body.signature_meaning,
        "signature_valid": True,
        "signed_by": current_user.user_id,
    }

    await write_audit(
        db=db,
        object_type="document_version",
        object_id=body.document_version_id,
        action="SIGN",
        before_state=before_state,
        after_state=after_state,
        actor_id=current_user.user_id,
        request=request,
        reason=body.reason,
    )

    return {
        "document_version_id": body.document_version_id,
        "signed": True,
        "signature_meaning": body.signature_meaning,
        "validation": validation_result,
    }
```

DSS는 PDF 서명 검증 시 문서 형식을 자동 판별하고, 검증 정책에 따라 서명과 타임스탬프를 검증할 수 있습니다. [github](https://github.com/esig/dss/blob/master/dss-cookbook/src/main/asciidoc/_chapters/webservices.adoc)

***

## ⑦ 운영 및 검증 완료 기준

| 영역 | 완료 기준 |
|---|---|
| **CAPA** | NC-CAPA-조치-효과성 확인까지 추적 |
| **교육** | 문서 승인 시 자동 할당, 이수기록 append-only |
| **RTM** | URS-설계-시험-증적 양방향 연결 |
| **CSV** | VMP-URS-Risk-RTM-IQ/OQ/PQ-VSR 연결 |
| **감사추적** | DB 트리거 + FastAPI 이중 기록 |
| **전자서명** | PAdES 서명·검증·변조 탐지 |
| **RAG** | 승인 문서만 검색, 출처·버전 인용 |

이 구조로 완성하면 **CAPA는 NC와 효과성 확인까지 추적**, **교육은 문서 승인과 자동 연계**, **RTM은 URS-설계-시험-증적까지 연결**, **CSV는 VMP부터 VSR까지 일관된 증적 체계**로 운영되는 규제 준수형 eQMS가 됩니다. [intelligentgraphicandcode](https://www.intelligentgraphicandcode.com/development/audit-trails)