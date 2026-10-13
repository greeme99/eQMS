아래는 **규제 변경 감지 → eQMS 자동 영향도 평가 → CSV 재검증 → VSR 갱신 → Slack·이메일 알림**까지 연결하는 종합 개발 가이드입니다. FDA는 공식 Guidance Documents 검색 페이지를 제공하며, Slack은 Incoming Webhook 기반 메시지 전송을 지원합니다. [fda](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/guidances)

***

## ① 전체 운영 구조

```text
[규제 소스]
   │
   ▼
[규제 모니터링 스크립트]
   │
   ▼
[변경 감지 + 키워드 분류]
   │
   ▼
[규제 변경 로그 저장]
   │
   ▼
[자동 영향도 평가]
   │
   ├── URS 영향
   ├── RTM 영향
   ├── CAPA 영향
   ├── 교육 영향
   └── CSV 재검증 필요성
   │
   ▼
[변경관리 + 재검증]
   │
   ▼
[VSR 갱신 + 운영 승인]
   │
   ▼
[Slack·이메일 알림]
```

FDA는 의료기기 관련 Guidance Documents를 별도 페이지로 제공하며, 이를 모니터링 대상으로 사용하는 것이 적절합니다.  Slack은 Incoming Webhook을 통해 채널에 메시지를 전송할 수 있으며, 비동기 클라이언트도 제공합니다. [fda](https://www.fda.gov/medical-devices/device-advice-comprehensive-regulatory-assistance/guidance-documents-medical-devices-and-radiation-emitting-products)

***

## ② 규제 모니터링 로그 스키마와 DB 구조

### 2.1 DB 스키마

```sql
-- 1. 규제 소스
CREATE TABLE regulatory_sources (
    source_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    url TEXT NOT NULL,
    check_frequency VARCHAR(20) NOT NULL
                  CHECK (check_frequency IN (
                      'DAILY','WEEKLY','MONTHLY','QUARTERLY'
                  )),
    last_checked_at TIMESTAMPTZ,
    last_content_hash CHAR(64),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. 규제 변경 감지 로그
CREATE TABLE regulatory_updates (
    update_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id VARCHAR(50) NOT NULL REFERENCES regulatory_sources(source_id),
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    title TEXT,
    url TEXT,
    content_hash CHAR(64) NOT NULL,
    previous_hash CHAR(64),
    matched_keywords TEXT[],
    change_type VARCHAR(30) NOT NULL DEFAULT 'UNKNOWN'
                CHECK (change_type IN (
                    'NEW_GUIDANCE','UPDATED_GUIDANCE',
                    'REVISED_REGULATION','UNKNOWN'
                )),
    impact_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
                  CHECK (impact_status IN (
                      'PENDING','UNDER_REVIEW','NO_IMPACT',
                      'IMPACT_ASSESSED','CHANGE_REQUIRED'
                  )),
    assessed_by UUID REFERENCES users(user_id),
    assessed_at TIMESTAMPTZ,
    impact_summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. 영향도 평가
CREATE TABLE regulatory_impact_assessments (
    assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    update_id UUID NOT NULL REFERENCES regulatory_updates(update_id),
    affected_urs TEXT[],
    affected_rtm TEXT[],
    affected_capa TEXT[],
    affected_training TEXT[],
    csv_revalidation_required BOOLEAN NOT NULL DEFAULT FALSE,
    revalidation_scope VARCHAR(30)
                      CHECK (revalidation_scope IN (
                          'NONE','TARGETED','FULL'
                      )),
    conclusion VARCHAR(30) NOT NULL
                CHECK (conclusion IN (
                    'NO_IMPACT','MINOR_IMPACT','MAJOR_IMPACT'
                )),
    assessor_id UUID NOT NULL REFERENCES users(user_id),
    assessed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    approval_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
                    CHECK (approval_status IN (
                        'PENDING','APPROVED','REJECTED'
                    )),
    approver_id UUID REFERENCES users(user_id),
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. CSV 재검증 워크플로
CREATE TABLE csv_revalidations (
    revalidation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assessment_id UUID NOT NULL REFERENCES regulatory_impact_assessments(assessment_id),
    revalidation_no VARCHAR(30) UNIQUE NOT NULL,
    scope VARCHAR(30) NOT NULL
          CHECK (scope IN ('TARGETED','FULL')),
    status VARCHAR(30) NOT NULL DEFAULT 'PLANNED'
           CHECK (status IN (
               'PLANNED','IN_PROGRESS','COMPLETED','CANCELLED'
           )),
    affected_urs TEXT[],
    affected_test_cases TEXT[],
    planned_start_date DATE,
    planned_end_date DATE,
    completed_at TIMESTAMPTZ,
    created_by UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 5. VSR 갱신 이력
CREATE TABLE vsr_revisions (
    revision_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    vsr_document_id UUID NOT NULL REFERENCES documents(document_id),
    revalidation_id UUID NOT NULL REFERENCES csv_revalidations(revalidation_id),
    revision_no VARCHAR(20) NOT NULL,
    revision_reason TEXT NOT NULL,
    revised_by UUID NOT NULL REFERENCES users(user_id),
    approved_by UUID REFERENCES users(user_id),
    approved_at TIMESTAMPTZ,
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT'
           CHECK (status IN (
               'DRAFT','IN_REVIEW','APPROVED','SUPERSEDED'
           )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 6. 알림 로그
CREATE TABLE notification_logs (
    notification_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    channel VARCHAR(20) NOT NULL
            CHECK (channel IN ('EMAIL','SLACK','EQMS')),
    recipient VARCHAR(200),
    subject TEXT,
    message TEXT,
    related_update_id UUID REFERENCES regulatory_updates(update_id),
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING'
            CHECK (status IN ('PENDING','SENT','FAILED')),
    sent_at TIMESTAMPTZ,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 7. 감사추적 연결
CREATE TABLE regulatory_audit_events (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_uuid UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type VARCHAR(50) NOT NULL,
    object_id UUID NOT NULL,
    action VARCHAR(30) NOT NULL,
    before_state JSONB,
    after_state JSONB,
    actor_id UUID,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    prev_hash CHAR(64),
    record_hash CHAR(64) NOT NULL
);

CREATE INDEX idx_regulatory_update_source
ON regulatory_updates(source_id, detected_at DESC);

CREATE INDEX idx_regulatory_update_status
ON regulatory_updates(impact_status, detected_at DESC);

CREATE INDEX idx_notification_update
ON notification_logs(related_update_id, created_at DESC);
```

### 2.2 감사추적 불변성 트리거

```sql
CREATE OR REPLACE FUNCTION reject_regulatory_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'regulatory_audit_events is append-only: % is not permitted', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_regulatory_audit_no_mutation
ON regulatory_audit_events;

CREATE TRIGGER trg_regulatory_audit_no_mutation
BEFORE UPDATE OR DELETE ON regulatory_audit_events
FOR EACH ROW
EXECUTE FUNCTION reject_regulatory_audit_mutation();
```

***

## ③ 규제 변경 시 eQMS 자동 영향도 평가 코드

### 3.1 영향도 평가 규칙

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

### 3.2 자동 영향도 평가 코드

```python
# app/services/regulatory_impact.py
from dataclasses import dataclass

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


@dataclass
class ImpactRule:
    keyword: str
    affected_urs: list[str]
    affected_rtm: list[str]
    affected_capa: list[str]
    affected_training: list[str]
    conclusion: str
    revalidation_scope: str


IMPACT_RULES = [
    ImpactRule(
        keyword="electronic signatures",
        affected_urs=["URS-SIG-001", "URS-SIG-002", "URS-SIG-003"],
        affected_rtm=["RTM-SIG-001", "RTM-SIG-002"],
        affected_capa=[],
        affected_training=["TRN-SIG-001"],
        conclusion="MAJOR_IMPACT",
        revalidation_scope="TARGETED",
    ),
    ImpactRule(
        keyword="audit trail",
        affected_urs=["URS-AT-001", "URS-AT-002", "URS-AT-003"],
        affected_rtm=["RTM-AT-001", "RTM-AT-002"],
        affected_capa=[],
        affected_training=["TRN-AT-001"],
        conclusion="MAJOR_IMPACT",
        revalidation_scope="TARGETED",
    ),
    ImpactRule(
        keyword="data integrity",
        affected_urs=["URS-AT-001", "URS-AT-002"],
        affected_rtm=["RTM-AT-001"],
        affected_capa=[],
        affected_training=["TRN-DI-001"],
        conclusion="MAJOR_IMPACT",
        revalidation_scope="TARGETED",
    ),
    ImpactRule(
        keyword="computer software assurance",
        affected_urs=["URS-CSV-001"],
        affected_rtm=["RTM-CSV-001"],
        affected_capa=[],
        affected_training=["TRN-CSV-001"],
        conclusion="MINOR_IMPACT",
        revalidation_scope="TARGETED",
    ),
    ImpactRule(
        keyword="design and development",
        affected_urs=["URS-RTM-001", "URS-RTM-002"],
        affected_rtm=["RTM-RTM-001"],
        affected_capa=[],
        affected_training=["TRN-DESIGN-001"],
        conclusion="MAJOR_IMPACT",
        revalidation_scope="TARGETED",
    ),
    ImpactRule(
        keyword="medical device file",
        affected_urs=["URS-DC-001", "URS-DC-002"],
        affected_rtm=["RTM-DC-001"],
        affected_capa=[],
        affected_training=["TRN-DMF-001"],
        conclusion="MINOR_IMPACT",
        revalidation_scope="TARGETED",
    ),
    ImpactRule(
        keyword="training",
        affected_urs=["URS-TRN-001", "URS-TRN-002"],
        affected_rtm=["RTM-TRN-001"],
        affected_capa=[],
        affected_training=["TRN-TRN-001"],
        conclusion="MINOR_IMPACT",
        revalidation_scope="NONE",
    ),
    ImpactRule(
        keyword="quality management system regulation",
        affected_urs=[
            "URS-DC-001", "URS-AT-001",
            "URS-SIG-001", "URS-CAPA-001",
            "URS-TRN-001", "URS-RTM-001",
        ],
        affected_rtm=[
            "RTM-DC-001", "RTM-AT-001",
            "RTM-SIG-001", "RTM-CAPA-001",
            "RTM-TRN-001", "RTM-RTM-001",
        ],
        affected_capa=["CAPA-QMS-001"],
        affected_training=["TRN-QMS-001"],
        conclusion="MAJOR_IMPACT",
        revalidation_scope="FULL",
    ),
]


def evaluate_impact(
    matched_keywords: list[str],
) -> dict:
    affected_urs = []
    affected_rtm = []
    affected_capa = []
    affected_training = []
    conclusions = []
    scopes = []

    for keyword in matched_keywords:
        for rule in IMPACT_RULES:
            if rule.keyword.lower() in keyword.lower():
                affected_urs.extend(rule.affected_urs)
                affected_rtm.extend(rule.affected_rtm)
                affected_capa.extend(rule.affected_capa)
                affected_training.extend(rule.affected_training)
                conclusions.append(rule.conclusion)
                scopes.append(rule.revalidation_scope)

    if not conclusions:
        return {
            "affected_urs": [],
            "affected_rtm": [],
            "affected_capa": [],
            "affected_training": [],
            "conclusion": "NO_IMPACT",
            "revalidation_scope": "NONE",
            "csv_revalidation_required": False,
        }

    if "MAJOR_IMPACT" in conclusions:
        conclusion = "MAJOR_IMPACT"
    elif "MINOR_IMPACT" in conclusions:
        conclusion = "MINOR_IMPACT"
    else:
        conclusion = "NO_IMPACT"

    if "FULL" in scopes:
        scope = "FULL"
    elif "TARGETED" in scopes:
        scope = "TARGETED"
    else:
        scope = "NONE"

    return {
        "affected_urs": sorted(set(affected_urs)),
        "affected_rtm": sorted(set(affected_rtm)),
        "affected_capa": sorted(set(affected_capa)),
        "affected_training": sorted(set(affected_training)),
        "conclusion": conclusion,
        "revalidation_scope": scope,
        "csv_revalidation_required": scope != "NONE",
    }


async def save_impact_assessment(
    db: AsyncSession,
    *,
    update_id: str,
    impact: dict,
    assessor_id: str,
) -> str:
    result = await db.execute(
        text("""
            INSERT INTO regulatory_impact_assessments (
                update_id,
                affected_urs,
                affected_rtm,
                affected_capa,
                affected_training,
                csv_revalidation_required,
                revalidation_scope,
                conclusion,
                assessor_id
            )
            VALUES (
                CAST(:update_id AS UUID),
                CAST(:affected_urs AS TEXT[]),
                CAST(:affected_rtm AS TEXT[]),
                CAST(:affected_capa AS TEXT[]),
                CAST(:affected_training AS TEXT[]),
                :csv_revalidation_required,
                :revalidation_scope,
                :conclusion,
                CAST(:assessor_id AS UUID)
            )
            RETURNING assessment_id
        """),
        {
            "update_id": update_id,
            "affected_urs": impact["affected_urs"],
            "affected_rtm": impact["affected_rtm"],
            "affected_capa": impact["affected_capa"],
            "affected_training": impact["affected_training"],
            "csv_revalidation_required": impact["csv_revalidation_required"],
            "revalidation_scope": impact["revalidation_scope"],
            "conclusion": impact["conclusion"],
            "assessor_id": assessor_id,
        },
    )

    await db.commit()
    return str(result.scalar_one())
```

### 3.3 자동 평가 트리거 API

```python
# app/routers/regulatory_impact.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user
from app.services.regulatory_impact import evaluate_impact, save_impact_assessment

router = APIRouter(prefix="/api/regulatory-impact")


class AutoImpactRequest(BaseModel):
    update_id: str
    matched_keywords: list[str]


@router.post("/auto-assess")
async def auto_assess_regulatory_impact(
    body: AutoImpactRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {
        "QA_ADMIN",
        "REGULATORY_AFFAIRS",
        "SYSTEM",
    }:
        raise HTTPException(status_code=403, detail="Not authorized")

    impact = evaluate_impact(
        matched_keywords=body.matched_keywords,
    )

    assessment_id = await save_impact_assessment(
        db=db,
        update_id=body.update_id,
        impact=impact,
        assessor_id=current_user.user_id,
    )

    await write_audit(
        db=db,
        object_type="regulatory_impact_assessment",
        object_id=assessment_id,
        action="CREATE",
        before_state=None,
        after_state={
            "update_id": body.update_id,
            "matched_keywords": body.matched_keywords,
            "conclusion": impact["conclusion"],
            "revalidation_scope": impact["revalidation_scope"],
            "affected_urs": impact["affected_urs"],
            "affected_rtm": impact["affected_rtm"],
        },
        actor_id=current_user.user_id,
        request=request,
        reason="Automatic regulatory impact assessment",
    )

    return {
        "assessment_id": assessment_id,
        **impact,
    }
```

***

## ④ CSV 재검증 워크플로와 VSR 갱신 로직

### 4.1 재검증 워크플로

```text
[규제 변경 감지]
        │
        ▼
[자동 영향도 평가]
        │
        ▼
[재검증 필요성 판단]
        │
        ├── NO_IMPACT → 종결
        ├── TARGETED → 대상 URS·시험 재검증
        └── FULL → 전체 CSV 재검증
        │
        ▼
[변경관리 개시]
        │
        ▼
[재검증 계획 수립]
        │
        ▼
[IQ/OQ/PQ 재실행]
        │
        ▼
[편차 처리]
        │
        ▼
[VSR 갱신]
        │
        ▼
[QA 승인]
```

### 4.2 재검증 생성 코드

```python
# app/services/csv_revalidation.py
from datetime import date

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession


async def create_csv_revalidation(
    db: AsyncSession,
    *,
    assessment_id: str,
    revalidation_no: str,
    scope: str,
    affected_urs: list[str],
    created_by: str,
) -> str:
    result = await db.execute(
        text("""
            INSERT INTO csv_revalidations (
                assessment_id,
                revalidation_no,
                scope,
                affected_urs,
                planned_start_date,
                planned_end_date,
                created_by
            )
            VALUES (
                CAST(:assessment_id AS UUID),
                :revalidation_no,
                :scope,
                CAST(:affected_urs AS TEXT[]),
                CURRENT_DATE,
                CURRENT_DATE + INTERVAL '30 days',
                CAST(:created_by AS UUID)
            )
            RETURNING revalidation_id
        """),
        {
            "assessment_id": assessment_id,
            "revalidation_no": revalidation_no,
            "scope": scope,
            "affected_urs": affected_urs,
            "created_by": created_by,
        },
    )

    await db.commit()
    return str(result.scalar_one())


async def create_vsr_revision(
    db: AsyncSession,
    *,
    vsr_document_id: str,
    revalidation_id: str,
    revision_no: str,
    revision_reason: str,
    revised_by: str,
) -> str:
    result = await db.execute(
        text("""
            INSERT INTO vsr_revisions (
                vsr_document_id,
                revalidation_id,
                revision_no,
                revision_reason,
                revised_by
            )
            VALUES (
                CAST(:vsr_document_id AS UUID),
                CAST(:revalidation_id AS UUID),
                :revision_no,
                :revision_reason,
                CAST(:revised_by AS UUID)
            )
            RETURNING revision_id
        """),
        {
            "vsr_document_id": vsr_document_id,
            "revalidation_id": revalidation_id,
            "revision_no": revision_no,
            "revision_reason": revision_reason,
            "revised_by": revised_by,
        },
    )

    await db.commit()
    return str(result.scalar_one())
```

### 4.3 재검증 API

```python
# app/routers/csv_revalidation.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user
from app.services.csv_revalidation import (
    create_csv_revalidation,
    create_vsr_revision,
)

router = APIRouter(prefix="/api/csv-revalidations")


class RevalidationRequest(BaseModel):
    assessment_id: str
    scope: str  # TARGETED | FULL
    affected_urs: list[str]
    vsr_document_id: str
    revision_reason: str


@router.post("")
async def create_revalidation(
    body: RevalidationRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_ADMIN", "VALIDATION_ENGINEER"}:
        raise HTTPException(status_code=403, detail="Not authorized")

    if body.scope not in {"TARGETED", "FULL"}:
        raise HTTPException(status_code=400, detail="Invalid scope")

    revalidation_no = await generate_revalidation_no(db)

    revalidation_id = await create_csv_revalidation(
        db=db,
        assessment_id=body.assessment_id,
        revalidation_no=revalidation_no,
        scope=body.scope,
        affected_urs=body.affected_urs,
        created_by=current_user.user_id,
    )

    revision_no = await generate_vsr_revision_no(db)

    revision_id = await create_vsr_revision(
        db=db,
        vsr_document_id=body.vsr_document_id,
        revalidation_id=revalidation_id,
        revision_no=revision_no,
        revision_reason=body.revision_reason,
        revised_by=current_user.user_id,
    )

    await write_audit(
        db=db,
        object_type="csv_revalidation",
        object_id=revalidation_id,
        action="CREATE",
        before_state=None,
        after_state={
            "assessment_id": body.assessment_id,
            "scope": body.scope,
            "affected_urs": body.affected_urs,
            "vsr_revision_id": revision_id,
        },
        actor_id=current_user.user_id,
        request=request,
        reason="CSV revalidation created from regulatory impact assessment",
    )

    return {
        "revalidation_id": revalidation_id,
        "revalidation_no": revalidation_no,
        "vsr_revision_id": revision_id,
        "status": "PLANNED",
    }
```

### 4.4 VSR 갱신 템플릿

```markdown
# Validation Summary Report (VSR) Revision

## 1. 문서 정보
- 문서번호: VSR-EQMS-001
- 개정번호: Rev.2
- 관련 재검증번호: CRV-2026-001
- 개정사유: FDA/GAMP 5 규제 변경 반영
- 개정자:
- 승인자:
- 승인일:

## 2. 규제 변경 요약
- 변경 소스:
- 변경 제목:
- 감지일:
- 매칭 키워드:
- 영향도 판정:

## 3. 영향도 평가 결과
| 영향 대상 | 영향 URS | 영향 RTM | 재검증 필요 |
|---|---|---|---|
| 감사추적 | URS-AT-001 | RTM-AT-001 | Yes |
| 전자서명 | URS-SIG-001 | RTM-SIG-001 | Yes |
| 교육 | URS-TRN-001 | RTM-TRN-001 | No |

## 4. 재검증 결과
| 시험 ID | 시험명 | 결과 | 증적 | 편차 |
|---|---|---|---|---|
| OQ-AT-001 | 감사추적 생성 | PASS | evidence_001.pdf | 없음 |
| OQ-AT-002 | 감사추적 불변성 | PASS | evidence_002.pdf | 없음 |
| OQ-SIG-001 | PAdES 서명 | PASS | evidence_003.pdf | 없음 |
| OQ-SIG-002 | 변조 탐지 | PASS | evidence_004.pdf | 없음 |

## 5. 잔여리스크
| Risk ID | 내용 | 완화책 | 수용여부 |
|---|---|---|---|

## 6. 결론
- 재검증 범위: TARGETED
- 재검증 결과: PASS
- VSR 갱신 승인 여부: APPROVED
- 운영 전환 가능 여부: YES

## 7. 승인
- QA Owner:
- System Owner:
- 승인일:
```

VSR은 시스템·범위, 프로토콜·수용기준, 결과, 편차, 미해결 항목, 추적성 확인, 릴리스 판정, 승인자 서명을 포함해야 하며, 조건부 승인도 문서화된 위험 평가를 전제로 허용됩니다. 

***

## ⑤ Slack 및 이메일 알림 연동 상세 코드

### 5.1 설정

```env
# .env
SMTP_HOST=smtp.company.com
SMTP_PORT=587
SMTP_USER=eqms-monitor@company.com
SMTP_PASSWORD=********
ALERT_EMAIL=qa-team@company.com

SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
```

Slack은 Incoming Webhook URL로 채널에 메시지를 전송하며, Python SDK는 `WebhookClient`와 비동기 `AsyncWebhookClient`를 제공합니다. [docs.slack](https://docs.slack.dev/tools/python-slack-sdk/webhook/index.html)

### 5.2 알림 서비스

```python
# app/services/notifier.py
import smtplib
from email.message import EmailMessage

import httpx
from slack_sdk.webhook.async_client import AsyncWebhookClient

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

SMTP_HOST = "smtp.company.com"
SMTP_PORT = 587
SMTP_USER = "eqms-monitor@company.com"
SMTP_PASSWORD = "********"
ALERT_EMAIL = "qa-team@company.com"

SLACK_WEBHOOK_URL = (
    "https://hooks.slack.com/services/"
    "T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
)


async def log_notification(
    db: AsyncSession,
    *,
    channel: str,
    recipient: str,
    subject: str,
    message: str,
    related_update_id: str | None,
    status: str,
    error_message: str | None = None,
):
    await db.execute(
        text("""
            INSERT INTO notification_logs (
                channel, recipient, subject, message,
                related_update_id, status, sent_at, error_message
            )
            VALUES (
                :channel, :recipient, :subject, :message,
                CAST(:related_update_id AS UUID),
                :status,
                CASE WHEN :status = 'SENT'
                     THEN now() ELSE NULL END,
                :error_message
            )
        """),
        {
            "channel": channel,
            "recipient": recipient,
            "subject": subject,
            "message": message,
            "related_update_id": related_update_id,
            "status": status,
            "error_message": error_message,
        },
    )

    await db.commit()


async def send_email(
    db: AsyncSession,
    *,
    subject: str,
    body: str,
    related_update_id: str | None = None,
    recipient: str = ALERT_EMAIL,
):
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = SMTP_USER
    message["To"] = recipient
    message.set_content(body)

    try:
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
            server.starttls()
            server.login(SMTP_USER, SMTP_PASSWORD)
            server.send_message(message)

        await log_notification(
            db=db,
            channel="EMAIL",
            recipient=recipient,
            subject=subject,
            message=body,
            related_update_id=related_update_id,
            status="SENT",
        )

    except Exception as error:
        await log_notification(
            db=db,
            channel="EMAIL",
            recipient=recipient,
            subject=subject,
            message=body,
            related_update_id=related_update_id,
            status="FAILED",
            error_message=str(error),
        )
        raise


async def send_slack(
    db: AsyncSession,
    *,
    message: str,
    related_update_id: str | None = None,
    channel: str = "#regulatory-watch",
):
    webhook = AsyncWebhookClient(SLACK_WEBHOOK_URL)

    blocks = [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": message,
            },
        }
    ]

    try:
        response = await webhook.send(
            text=message,
            blocks=blocks,
        )

        if response.status_code != 200:
            raise RuntimeError(response.body)

        await log_notification(
            db=db,
            channel="SLACK",
            recipient=channel,
            subject="Regulatory Update",
            message=message,
            related_update_id=related_update_id,
            status="SENT",
        )

    except Exception as error:
        await log_notification(
            db=db,
            channel="SLACK",
            recipient=channel,
            subject="Regulatory Update",
            message=message,
            related_update_id=related_update_id,
            status="FAILED",
            error_message=str(error),
        )
        raise
```

### 5.3 규제 변경 알림 함수

```python
# app/services/regulatory_alert.py
from app.services.notifier import send_email, send_slack


async def send_regulatory_change_alert(
    db,
    *,
    update_id: str,
    source_name: str,
    source_url: str,
    title: str,
    matched_keywords: list[str],
    impact: dict,
):
    message = "\n".join(
        [
            f"*[Regulatory Update Detected]*",
            f"*Source:* {source_name}",
            f"*Title:* {title}",
            f"*URL:* {source_url}",
            f"*Matched Keywords:* {', '.join(matched_keywords)}",
            "",
            f"*Impact Conclusion:* {impact['conclusion']}",
            f"*CSV Revalidation:* {impact['revalidation_scope']}",
            f"*Affected URS:* {', '.join(impact['affected_urs']) or 'None'}",
            f"*Affected RTM:* {', '.join(impact['affected_rtm']) or 'None'}",
            f"*Affected CAPA:* {', '.join(impact['affected_capa']) or 'None'}",
            f"*Affected Training:* {', '.join(impact['affected_training']) or 'None'}",
        ]
    )

    email_body = message.replace("*", "")

    await send_email(
        db=db,
        subject=f"[Regulatory Update] {source_name}",
        body=email_body,
        related_update_id=update_id,
    )

    await send_slack(
        db=db,
        message=message,
        related_update_id=update_id,
    )
```

### 5.4 모니터링 스크립트에 알림 연결

```python
# regulatory/monitor.py
from app.services.regulatory_alert import send_regulatory_change_alert
from app.services.regulatory_impact import evaluate_impact


async def check_source(db, source):
    async with httpx.AsyncClient(
        timeout=30,
        follow_redirects=True,
    ) as client:
        response = await client.get(source.url)
        response.raise_for_status()
        html = response.text

    content_hash = hashlib.sha256(html.encode("utf-8")).hexdigest()
    previous = await get_previous_state(db, source.source_id)

    previous_hash = previous.last_content_hash if previous else None

    matched_keywords = extract_matched_keywords(
        html=html,
        keywords=source.keywords,
    )

    has_change = previous_hash is not None and previous_hash != content_hash
    has_keyword = len(matched_keywords) > 0

    if has_change and has_keyword:
        title = await extract_page_title(html)

        update_id = await save_regulatory_update(
            db=db,
            source_id=source.source_id,
            title=title,
            url=source.url,
            content_hash=content_hash,
            matched_keywords=matched_keywords,
        )

        impact = evaluate_impact(
            matched_keywords=matched_keywords,
        )

        await send_regulatory_change_alert(
            db=db,
            update_id=update_id,
            source_name=source.name,
            source_url=source.url,
            title=title,
            matched_keywords=matched_keywords,
            impact=impact,
        )

        return update_id

    await upsert_source(
        db=db,
        source_id=source.source_id,
        name=source.name,
        url=source.url,
        check_frequency=source.check_frequency,
        content_hash=content_hash,
    )

    await db.commit()
    return None
```

***

## ⑦ 운영 및 검증 완료 기준

| 영역 | 완료 기준 |
|---|---|
| **규제 모니터링** | FDA·GAMP 변경 감지, 로그 저장, 알림 발송 |
| **자동 영향도 평가** | 키워드 기반 URS·RTM·CAPA·교육 영향 식별 |
| **CSV 재검증** | TARGETED 또는 FULL 재검증 계획 생성 |
| **VSR 갱신** | 재검증 결과 기반 개정번호·사유·승인 기록 |
| **CAPA** | NC-CAPA-조치-효과성 확인까지 추적 |
| **교육** | 문서 승인 시 자동 할당, 이수기록 append-only |
| **RTM** | URS-설계-시험-증적 양방향 연결 |
| **감사추적** | DB 트리거 + FastAPI 이중 기록 |
| **알림** | 이메일·Slack 발송 성공·실패 로그 |

FDA는 공식 Guidance Documents 검색 페이지를 통해 최신 가이던스를 확인할 수 있도록 하며, 의료기기 관련 가이던스는 별도 CDRH 페이지에서 제공됩니다.  Slack은 Incoming Webhook 기반 메시지 전송과 비동기 클라이언트를 제공하므로, 규제 변경 알림 채널로 활용하기에 적합합니다. [fda](https://www.fda.gov/regulatory-information/search-fda-guidance-documents/guidances)