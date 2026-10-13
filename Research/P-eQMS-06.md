아래는 **CAPA → 교육 → 설계추적성(RTM) → CSV 패키지 → FastAPI 감사추적 연동**까지 이어지는 확장 개발 가이드입니다. 모든 품질기록은 문서버전, 승인, 서명, 감사추적과 연결되도록 설계하며, 교육 이수와 CAPA 조치도 append-only 감사기록으로 관리합니다. RTM은 요구사항에서 설계·시험·검증증적까지 양방향으로 추적하는 구조로 구성하는 것이 표준입니다. [inflectra](https://www.inflectra.com/Ideas/Topic/Requirements-Traceability-Matrix-Template.aspx)

***

## ① 확장 개발 로드맵

| 단계 | 기간 | 목표 | 핵심 산출물 |
|---|---:|---|---|
| **확장 1** | 2주 | CAPA 관리 | NC, CAPA, 원인분석, 조치, 효과성 |
| **확장 2** | 2주 | 교육·이수관리 | 교육과정, 할당, 이수, 인증서 |
| **확장 3** | 2주 | 설계추적성 | Design File, RTM, V&V 연계 |
| **확장 4** | 3~4주 | CSV 패키지 | VMP, URS, Risk, IQ/OQ/PQ, VSR |
| **지속운영** | 상시 | 감사추적·변경통제 | Audit, Change Control, Periodic Review |

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
-- CAPA 변경 감사 트리거 함수
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

-- NC 변경 감사 트리거 함수
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

-- CAPA 조치 변경 감사 트리거 함수
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

## ③ CSV 패키지: 검증계획 및 URS 템플릿

### 3.1 CSV 패키지 구성

| 문서 | 목적 | 작성 시점 |
|---|---|---|
| **VMP** | 검증 범위·전략·역할 정의 | 프로젝트 시작 |
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

RTM은 요구사항을 원천, 설계, 시험, 검증증적까지 양방향으로 연결하며, 요구사항 ID·설계·시험·결과·위험통제·규제 참조를 포함하는 구조가 권장됩니다. [inflectra](https://www.inflectra.com/Ideas/Topic/Requirements-Traceability-Matrix-Template.aspx)

### 3.2 Validation Master Plan 템플릿

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
- 주요 모듈: 문서관리, 감사추적, 전자서명, CAPA, 교육, 설계추적성, RAG
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
- URS-위험-테스트 추적성 유지
- 감사추적·전자서명 우선 검증
- 변경 발생 시 영향평가 및 재검증

## 8. 수용기준
- High Risk 테스트 100% 통과
- 모든 URS에 대응 테스트 존재
- 편차 없음 또는 승인된 편차만 존재
- 감사추적 증적 완전성 확보
```

### 3.3 URS 템플릿

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
| URS-CAPA-003 | FR | CAPA 종결 시 효과성 확인이 필요하다 | 미완료 조치 시 종결 차단 | High | OQ |

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

***

## ④ 설계추적성 매트릭스(RTM) 구현

### 4.1 RTM 설계 원칙

RTM은 요구사항, 설계, 시험, 검증증적, 위험통제, 규제 참조를 연결합니다. 각 요구사항은 고유 ID를 부여하고, 설계·시험·결과·결함까지 양방향으로 추적해야 합니다. [inflectra](https://www.inflectra.com/Ideas/Topic/Requirements-Traceability-Matrix-Template.aspx)

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
[Test Result]
        │
        ▼
[Validation Evidence]
```

### 4.2 RTM DB 스키마

```sql
-- 요구사항
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

-- 설계 항목
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

-- 시험 케이스
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

-- 시험 실행 결과
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

-- 추적성 관계
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
    UNIQUE (source_type, source_id, target_type, target_id, relation_type)
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

## ⑤ 이수관리 및 교육 모듈 DB 구조

### 5.1 설계 원칙

- 교육과정, 교육버전, 할당, 이수기록을 분리합니다.
- 문서 승인 시 대상 역할에 따라 교육을 자동 할당합니다.
- 이수기록은 append-only로 관리하고, 재교육은 새로운 이수기록으로 생성합니다.
- 교육기록은 사용자, 과정, 문서버전, 이수일, 평가, 인증서와 연결합니다.
- LMS 구조는 학습자, 등록, 콘텐츠, 평가, 이수기록, 감사로그를 분리해 관리하는 방식이 권장됩니다. [softr](https://www.softr.io/database-template/lms)

### 5.2 교육 스키마

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

-- 6. 교육기록 불변성
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

### 5.3 문서 승인 시 교육 자동할당 트리거

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

***

## ⑥ FastAPI 미들웨어 감사추적 연동

### 6.1 요청 컨텍스트 미들웨어

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

### 6.2 감사추적 서비스

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

### 6.3 CAPA 생성 API 적용

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

### 6.4 앱 등록

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

***

## ⑦ CSV 검증 패키지 작성 절차

### 7.1 작성 순서

```text
1. VMP 작성
2. URS 작성 및 승인
3. 위험평가 수행
4. 기능명세·설계문서 작성
5. RTM 작성
6. IQ/OQ/PQ 프로토콜 작성
7. 테스트 실행 및 증적 수집
8. 편차 처리
9. VSR 작성
10. SOP·교육기록 완비
11. 운영전환 승인
```

### 7.2 RTM 예시

| URS ID | 위험 ID | 설계 ID | 시험 ID | 시험결과 | 증적 | 규제 참조 |
|---|---|---|---|---|---|---|
| URS-DC-001 | R-003 | DS-DOC-001 | OQ-DOC-001 | PASS | evidence_001.pdf | 21 CFR Part 11 |
| URS-AT-001 | R-001 | DS-AT-001 | OQ-AT-001 | PASS | evidence_002.pdf | 21 CFR Part 11 |
| URS-AT-002 | R-001 | DS-AT-002 | OQ-AT-002 | PASS | evidence_003.pdf | 21 CFR Part 11 |
| URS-SIG-001 | R-002 | DS-SIG-001 | OQ-SIG-001 | PASS | evidence_004.pdf | 21 CFR Part 11 |
| URS-SIG-002 | R-002 | DS-SIG-002 | OQ-SIG-002 | PASS | evidence_005.pdf | 21 CFR Part 11 |
| URS-CAPA-003 | R-006 | DS-CAPA-003 | OQ-CAPA-003 | PASS | evidence_006.pdf | ISO 13485 |
| URS-TRN-003 | R-007 | DS-TRN-003 | OQ-TRN-003 | PASS | evidence_007.pdf | ISO 13485 |
| URS-RAG-001 | R-004 | DS-RAG-001 | OQ-RAG-001 | PASS | evidence_008.pdf | GAMP 5 |

RTM은 요구사항의 원천, 설계, 시험, 검증 결과, 위험통제, 규제 참조를 한 행에서 확인할 수 있도록 구성해야 하며, 요구사항 변경 시에도 지속 갱신해야 합니다. [inflectra](https://www.inflectra.com/Ideas/Topic/Requirements-Traceability-Matrix-Template.aspx)

### 7.3 검증 완료 기준

- 모든 High Risk URS에 대응 OQ/PQ 테스트가 존재
- 모든 테스트 결과가 RTM에 연결
- 모든 편차가 종결 또는 승인된 상태
- 감사추적 해시체인 검증 통과
- 전자서명 변조 탐지 테스트 통과
- RAG가 승인 문서만 검색하고 출처를 인용
- 교육기록·SOP·백업복구 증적 완비

이 구조로 완성하면 **CAPA는 NC와 효과성 확인까지 추적**, **교육은 문서 승인과 자동 연계**, **RTM은 URS-설계-시험-증적까지 연결**, **CSV는 VMP부터 VSR까지 일관된 증적 체계**로 운영되는 규제 준수형 eQMS가 됩니다. [jamasoftware](https://www.jamasoftware.com/requirements-management-guide/requirements-traceability/traceability-matrix/)