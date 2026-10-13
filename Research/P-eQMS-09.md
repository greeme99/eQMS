아래는 **규제 모니터링 → 영향도 평가 → CAPA·교육·RTM·CSV 연계**까지 포함한 규제 준수형 eQMS 개발 가이드입니다. FDA는 공식 Guidance Documents 검색 페이지를 제공하며, ISPE는 GAMP 5 2판을 통해 GxP 컴퓨터화 시스템의 위험 기반 검증·데이터 무결성·규제 준수를 다룹니다. [fda](https://www.fda.gov/regulatory-information)

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
[eQMS 영향도 평가]
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
```

***

## ② 규제 모니터링 Python 스크립트 전체 코드

### 2.1 설치

```bash
pip install httpx beautifulsoup4 schedule python-dotenv sqlalchemy asyncpg
```

### 2.2 설정 파일

```env
# .env
SMTP_HOST=smtp.company.com
SMTP_PORT=587
SMTP_USER=eqms-monitor@company.com
SMTP_PASSWORD=********
ALERT_EMAIL=qa-team@company.com

SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxx/yyy/zzz

DATABASE_URL=postgresql+asyncpg://eqms:eqms@localhost:5432/eqms
```

### 2.3 규제 소스 정의

```python
# regulatory/sources.py
from dataclasses import dataclass


@dataclass
class RegulatorySource:
    source_id: str
    name: str
    url: str
    keywords: list[str]
    check_frequency: str


REGULATORY_SOURCES = [
    RegulatorySource(
        source_id="fda_guidance",
        name="FDA Guidance Documents",
        url="https://www.fda.gov/regulatory-information/search-fda-guidance-documents",
        keywords=[
            "21 CFR Part 11",
            "electronic records",
            "electronic signatures",
            "computer software assurance",
            "data integrity",
        ],
        check_frequency="weekly",
    ),
    RegulatorySource(
        source_id="ecfr_part_11",
        name="eCFR 21 CFR Part 11",
        url="https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11",
        keywords=[
            "electronic records",
            "electronic signatures",
            "audit trail",
        ],
        check_frequency="weekly",
    ),
    RegulatorySource(
        source_id="ecfr_part_820",
        name="eCFR 21 CFR Part 820",
        url="https://www.ecfr.gov/current/title-21/chapter-I/subchapter-H/part-820",
        keywords=[
            "quality management system regulation",
            "design and development",
            "medical device file",
        ],
        check_frequency="weekly",
    ),
    RegulatorySource(
        source_id="ispe_gamp",
        name="ISPE GAMP",
        url="https://ispe.org/topics/gamp",
        keywords=[
            "GAMP 5",
            "computerized systems",
            "data integrity",
            "validation",
        ],
        check_frequency="monthly",
    ),
]
```

FDA는 공식 Guidance Documents 검색 페이지를 제공하며, ISPE GAMP는 GxP 컴퓨터화 시스템의 환자 안전·제품 품질·데이터 무결성을 목표로 하는 위험 기반 접근을 제시합니다. [fda](https://www.fda.gov/regulatory-information)

### 2.4 데이터베이스 모델

```sql
CREATE TABLE regulatory_sources (
    source_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    url TEXT NOT NULL,
    check_frequency VARCHAR(20) NOT NULL,
    last_checked_at TIMESTAMPTZ,
    last_content_hash CHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE regulatory_updates (
    update_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source_id VARCHAR(50) NOT NULL REFERENCES regulatory_sources(source_id),
    detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    title TEXT,
    url TEXT,
    content_hash CHAR(64) NOT NULL,
    matched_keywords TEXT[],
    impact_status VARCHAR(30) NOT NULL DEFAULT 'PENDING'
                  CHECK (impact_status IN (
                      'PENDING','UNDER_REVIEW','NO_IMPACT',
                      'IMPACT_ASSESSED','CHANGE_REQUIRED'
                  )),
    assessed_by UUID,
    assessed_at TIMESTAMPTZ,
    impact_summary TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE regulatory_impact_assessments (
    assessment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    update_id UUID NOT NULL REFERENCES regulatory_updates(update_id),
    affected_urs TEXT[],
    affected_rtm TEXT[],
    affected_capa TEXT[],
    affected_training TEXT[],
    csv_revalidation_required BOOLEAN NOT NULL DEFAULT FALSE,
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
    approved_at TIMESTAMPTZ
);
```

### 2.5 모니터링 스크립트 전체 코드

```python
# regulatory/monitor.py
import asyncio
import hashlib
import os
import smtplib
from datetime import datetime, timezone
from email.message import EmailMessage

import httpx
from bs4 import BeautifulSoup
from dotenv import load_dotenv
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from regulatory.sources import REGULATORY_SOURCES

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL")
SMTP_HOST = os.getenv("SMTP_HOST")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD")
ALERT_EMAIL = os.getenv("ALERT_EMAIL")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

engine = create_async_engine(DATABASE_URL)
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_previous_state(
    db: AsyncSession,
    source_id: str,
):
    result = await db.execute(
        text("""
            SELECT last_content_hash, last_checked_at
            FROM regulatory_sources
            WHERE source_id = :source_id
        """),
        {"source_id": source_id},
    )

    return result.first()


async def upsert_source(
    db: AsyncSession,
    source_id: str,
    name: str,
    url: str,
    check_frequency: str,
    content_hash: str,
):
    await db.execute(
        text("""
            INSERT INTO regulatory_sources (
                source_id, name, url, check_frequency,
                last_checked_at, last_content_hash
            )
            VALUES (
                :source_id, :name, :url, :check_frequency,
                :checked_at, :content_hash
            )
            ON CONFLICT (source_id)
            DO UPDATE SET
                name = EXCLUDED.name,
                url = EXCLUDED.url,
                check_frequency = EXCLUDED.check_frequency,
                last_checked_at = EXCLUDED.last_checked_at,
                last_content_hash = EXCLUDED.last_content_hash
        """),
        {
            "source_id": source_id,
            "name": name,
            "url": url,
            "check_frequency": check_frequency,
            "checked_at": datetime.now(timezone.utc),
            "content_hash": content_hash,
        },
    )


async def save_regulatory_update(
    db: AsyncSession,
    source_id: str,
    title: str,
    url: str,
    content_hash: str,
    matched_keywords: list[str],
):
    result = await db.execute(
        text("""
            INSERT INTO regulatory_updates (
                source_id, title, url, content_hash, matched_keywords
            )
            VALUES (
                :source_id, :title, :url, :content_hash, :matched_keywords
            )
            RETURNING update_id
        """),
        {
            "source_id": source_id,
            "title": title,
            "url": url,
            "content_hash": content_hash,
            "matched_keywords": matched_keywords,
        },
    )

    return str(result.scalar_one())


async def extract_page_title(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")

    if soup.title and soup.title.string:
        return soup.title.string.strip()

    return "Untitled regulatory page"


def extract_matched_keywords(
    html: str,
    keywords: list[str],
) -> list[str]:
    content = html.lower()

    return [
        keyword
        for keyword in keywords
        if keyword.lower() in content
    ]


async def send_email_alert(
    subject: str,
    body: str,
):
    message = EmailMessage()
    message["Subject"] = subject
    message["From"] = SMTP_USER
    message["To"] = ALERT_EMAIL
    message.set_content(body)

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.starttls()
        server.login(SMTP_USER, SMTP_PASSWORD)
        server.send_message(message)


async def send_slack_alert(message: str):
    if not SLACK_WEBHOOK_URL:
        return

    async with httpx.AsyncClient(timeout=30) as client:
        await client.post(
            SLACK_WEBHOOK_URL,
            json={"text": message},
        )


async def check_source(
    db: AsyncSession,
    source,
):
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

        alert_body = "\n".join(
            [
                f"Source: {source.name}",
                f"URL: {source.url}",
                f"Title: {title}",
                f"Matched keywords: {', '.join(matched_keywords)}",
                "",
                "Please assess the impact on eQMS URS, RTM, CAPA, training, and CSV.",
            ]
        )

        await send_email_alert(
            subject=f"[Regulatory Update] {source.name}",
            body=alert_body,
        )

        await send_slack_alert(
            f"[Regulatory Update] {source.name}\n"
            f"Matched: {', '.join(matched_keywords)}\n"
            f"{source.url}"
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


async def run_monitoring():
    async with AsyncSessionLocal() as db:
        for source in REGULATORY_SOURCES:
            try:
                await check_source(db, source)
            except Exception as error:
                await db.rollback()
                print(f"Monitoring failed for {source.source_id}: {error}")


if __name__ == "__main__":
    asyncio.run(run_monitoring())
```

### 2.6 주기 실행

```python
# regulatory/scheduler.py
import schedule
import time

from regulatory.monitor import run_monitoring


def weekly_fda_check():
    print("Running weekly FDA monitoring...")
    asyncio.run(run_monitoring())


def monthly_gamp_check():
    print("Running monthly GAMP monitoring...")
    asyncio.run(run_monitoring())


schedule.every().monday.at("09:00").do(weekly_fda_check)
schedule.every().month.do(monthly_gamp_check)

while True:
    schedule.run_pending()
    time.sleep(60)
```

Python의 `schedule` 라이브러리는 주기 작업 실행을 위한 간단한 스케줄링 패턴을 제공하며, 이메일·Slack 알림과 조합해 규제 변경 감시에 활용할 수 있습니다. [dev](https://dev.to/nithinbharathwaj/python-automation-guide-7-scripts-for-efficient-system-administration-with-code-examples-30fa)

***

## ③ 규제 변경 시 eQMS 영향도 평가 프로세스

### 3.1 영향도 평가 흐름

```text
[규제 변경 감지]
        │
        ▼
[변경 내용 분류]
        │
        ▼
[영향 대상 식별]
        │
        ├── URS
        ├── RTM
        ├── CAPA
        ├── 교육
        └── CSV
        │
        ▼
[위험도 평가]
        │
        ▼
[재검증 필요성 판단]
        │
        ▼
[변경관리 개시]
        │
        ▼
[QA 승인]
```

### 3.2 영향도 평가 API

```python
# app/routers/regulatory_impact.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/api/regulatory-impact")


class ImpactAssessmentRequest(BaseModel):
    update_id: str
    affected_urs: list[str]
    affected_rtm: list[str]
    affected_capa: list[str]
    affected_training: list[str]
    csv_revalidation_required: bool
    conclusion: str  # NO_IMPACT | MINOR_IMPACT | MAJOR_IMPACT
    impact_summary: str


@router.post("")
async def assess_regulatory_impact(
    body: ImpactAssessmentRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_ADMIN", "REGULATORY_AFFAIRS"}:
        raise HTTPException(status_code=403, detail="Not authorized")

    if body.conclusion not in {
        "NO_IMPACT",
        "MINOR_IMPACT",
        "MAJOR_IMPACT",
    }:
        raise HTTPException(status_code=400, detail="Invalid conclusion")

    assessment_id = await insert_impact_assessment(
        db=db,
        update_id=body.update_id,
        affected_urs=body.affected_urs,
        affected_rtm=body.affected_rtm,
        affected_capa=body.affected_capa,
        affected_training=body.affected_training,
        csv_revalidation_required=body.csv_revalidation_required,
        conclusion=body.conclusion,
        impact_summary=body.impact_summary,
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
            "conclusion": body.conclusion,
            "csv_revalidation_required": body.csv_revalidation_required,
            "affected_urs": body.affected_urs,
            "affected_rtm": body.affected_rtm,
        },
        actor_id=current_user.user_id,
        request=request,
        reason="Regulatory change impact assessment",
    )

    return {
        "assessment_id": assessment_id,
        "conclusion": body.conclusion,
        "csv_revalidation_required": body.csv_revalidation_required,
    }
```

### 3.3 영향도 판정 기준

| 규제 변경 유형 | 영향 대상 | 판정 | 조치 |
|---|---|---|---|
| 용어·참고자료 변경 | URS, SOP | NO_IMPACT | 문서 참조 갱신 |
| 감사추적 요구 강화 | URS, DB, RTM | MAJOR_IMPACT | 설계변경 + OQ 재시험 |
| 전자서명 요구 변경 | URS, DSS, RTM | MAJOR_IMPACT | 서명 워크플로 재검증 |
| 데이터무결성 요구 강화 | DB, 백업, 감사추적 | MAJOR_IMPACT | CSV 재검증 |
| 교육 관련 요구 변경 | 교육모듈, SOP | MINOR_IMPACT | 교육할당 및 재교육 |
| GAMP 5 해석 변경 | VMP, 위험평가, RTM | MINOR~MAJOR | 검증전략 재검토 |

***

## ④ CSV VMP 및 URS 검증 템플릿

### 4.1 Validation Master Plan(VMP)

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

### 4.2 URS 템플릿

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

***

## ⑤ 교육 관리 DB 스키마와 트리거 코드

### 5.1 교육 프로세스

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

### 5.4 교육 이수 감사 트리거

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

## ⑥ 운영 및 검증 완료 기준

| 영역 | 완료 기준 |
|---|---|
| **규제 모니터링** | FDA·GAMP 변경 감지, 알림, 감사기록 |
| **영향도 평가** | URS·RTM·CAPA·교육·CSV 영향 식별 |
| **CAPA** | NC-CAPA-조치-효과성 확인까지 추적 |
| **교육** | 문서 승인 시 자동 할당, 이수기록 append-only |
| **RTM** | URS-설계-시험-증적 양방향 연결 |
| **CSV** | VMP-URS-Risk-RTM-IQ/OQ/PQ-VSR 연결 |
| **감사추적** | DB 트리거 + FastAPI 이중 기록 |
| **전자서명** | PAdES 서명·검증·변조 탐지 |
| **RAG** | 승인 문서만 검색, 출처·버전 인용 |

이 구조로 완성하면 **CAPA는 NC와 효과성 확인까지 추적**, **교육은 문서 승인과 자동 연계**, **RTM은 URS-설계-시험-증적까지 연결**, **CSV는 VMP부터 VSR까지 일관된 증적 체계**로 운영되는 규제 준수형 eQMS가 됩니다. [fda](https://www.fda.gov/regulatory-information)