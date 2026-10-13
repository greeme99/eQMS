아래는 **감사추적 → 문서버전 → 전자서명 → RAG 검색 → CAPA·교육·설계추적성·CSV 확장**까지 연결하는 종합 개발 가이드입니다. 핵심 설계 원칙은 **규제 기록은 append-only로 보존**, **문서 원본은 무결성 저장소에 보관**, **모든 승인·서명·검색 행위는 감사추적과 연결**하는 것입니다. PostgreSQL 공식 문서도 트리거 기반 변경 감사 방식을 표준 패턴으로 제시하며, 해시 체인과 변경 차단 트리거를 결합하면 무결성 검증이 강화됩니다. [postgresql](https://www.postgresql.org/docs/current/plpgsql-trigger.html)

***

## ① Executive Summary

1. **4주 MVP 목표**는 감사추적, 문서 버전관리, PAdES 전자서명, 승인 SOP RAG 검색의 최소 동작 구조를 확보하는 것입니다.
2. **감사추적은 애플리케이션 로그만으로 부족**합니다. PostgreSQL 트리거로 데이터 변경 자체를 기록하고, FastAPI 미들웨어로 사용자·IP·사유·비즈니스 맥락을 보강해야 합니다. [postgresql](https://www.postgresql.org/docs/current/plpgsql-trigger.html)
3. **전자서명은 DSS의 PAdES REST 서비스**로 구현하고, 서명 생성과 검증을 분리된 API로 운영합니다. DSS는 PAdES·XAdES·CAdES·JAdES 서명 생성·확장·검증을 지원합니다. 
4. **Odoo는 품질운영 기록**, Nextcloud는 문서 원본 저장소, FastAPI는 규제 통제 계층으로 분리합니다. Odoo-Nextcloud 문서 허브는 WebDAV 기반으로 레코드와 문서를 연결합니다. 
5. **CSV는 개발 완료 후가 아니라 URS·위험평가와 병행**해 준비하며, IQ는 설치·환경, OQ는 기능·오류조건, PQ는 실제 업무 시나리오를 검증합니다. [casrai](https://casrai.org/guides/computer-system-validation-csv-gamp-5-iq-oq-pq)

***

## ② 전체 개발 로드맵

| 단계 | 기간 | 목표 | 핵심 산출물 |
|---|---:|---|---|
| **Week 1** | 5일 | 감사추적 PoC | `audit_events`, 트리거, FastAPI 미들웨어 |
| **Week 2** | 5일 | 문서등록·버전관리 | 문서 API, 버전 API, SHA-256 무결성 |
| **Week 3** | 5일 | 전자서명 PoC | DSS PAdES 서명·검증, 서명 감사기록 |
| **Week 4** | 5일 | RAG 파일럿 | 승인 SOP 색인, 질의 API, 정확도 평가 |
| **Week 5~6** | 2주 | CAPA·교육 | NC/CAPA 워크플로, 교육이수 |
| **Week 7~8** | 2주 | 설계추적성·CSV | Design File, RTM, IQ/OQ/PQ 패키지 |

***

## ③ 감사추적 PostgreSQL 트리거 및 미들웨어

### 3.1 설계 원칙

- 감사기록 테이블은 `INSERT`와 `SELECT`만 허용합니다.
- `UPDATE`, `DELETE`는 트리거에서 예외를 발생시켜 차단합니다.
- 각 감사기록은 이전 해시와 현재 해시를 연결하는 해시 체인을 사용합니다.
- 애플리케이션 사용자 ID, IP, User-Agent, 변경 사유는 FastAPI 계층에서 기록합니다.
- PostgreSQL은 트리거 함수로 INSERT·UPDATE·DELETE를 감사 테이블에 기록하는 방식을 공식 문서에서 제시합니다. [postgresql](https://www.postgresql.org/docs/current/plpgsql-trigger.html)

### 3.2 감사추적 테이블

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

CREATE INDEX idx_audit_object
ON audit_events(object_type, object_id, occurred_at DESC);

CREATE INDEX idx_audit_actor
ON audit_events(actor_id, occurred_at DESC);

CREATE INDEX idx_audit_action
ON audit_events(action, occurred_at DESC);
```

### 3.3 변경 차단 트리거

```sql
CREATE OR REPLACE FUNCTION reject_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION
        'audit_events is append-only: % is not permitted', TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_no_mutation ON audit_events;

CREATE TRIGGER trg_audit_no_mutation
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW
EXECUTE FUNCTION reject_audit_mutation();
```

이 패턴은 감사 로그의 변경·삭제를 트리거 수준에서 차단하고, 해시 체인으로 무단 변경을 탐지할 수 있게 합니다. [waterutility](https://www.waterutility.org/core-architecture-sdwa-compliance-taxonomy/audit-trail-data-lineage/building-append-only-audit-logs-in-postgresql/)

### 3.4 문서 테이블 감사 트리거

```sql
CREATE OR REPLACE FUNCTION fn_audit_document_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_prev_hash CHAR(64);
    v_payload JSONB;
    v_hash CHAR(64);
BEGIN
    SELECT record_hash
    INTO v_prev_hash
    FROM audit_events
    WHERE object_type = 'document'
      AND object_id = COALESCE(NEW.document_id, OLD.document_id)
    ORDER BY occurred_at DESC, audit_id DESC
    LIMIT 1;

    v_payload := jsonb_build_object(
        'object_type', 'document',
        'object_id', COALESCE(NEW.document_id, OLD.document_id),
        'action', TG_OP,
        'before_state', CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(OLD) END,
        'after_state', CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END,
        'occurred_at', clock_timestamp(),
        'prev_hash', v_prev_hash
    );

    v_hash := encode(
        digest(v_payload::text, 'sha256'),
        'hex'
    );

    INSERT INTO audit_events (
        object_type,
        object_id,
        action,
        before_state,
        after_state,
        actor_id,
        actor_ip,
        user_agent,
        reason,
        prev_hash,
        record_hash
    )
    VALUES (
        'document',
        COALESCE(NEW.document_id, OLD.document_id),
        TG_OP,
        CASE WHEN TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE to_jsonb(OLD) END,
        CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END,
        NULL,
        NULL,
        NULL,
        'Database-level change',
        v_prev_hash,
        v_hash
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_document_audit ON documents;

CREATE TRIGGER trg_document_audit
AFTER INSERT OR UPDATE OR DELETE ON documents
FOR EACH ROW
EXECUTE FUNCTION fn_audit_document_change();
```

### 3.5 FastAPI 감사추적 미들웨어

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
        {"object_type": object_type, "object_id": object_id},
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
        "reason": reason,
        "occurred_at": occurred_at,
        "prev_hash": prev_hash,
    }

    record_hash = make_hash(payload)

    result = await db.execute(
        text("""
            INSERT INTO audit_events (
                event_uuid, object_type, object_id, action,
                before_state, after_state,
                actor_id, actor_ip, user_agent, reason,
                occurred_at, prev_hash, record_hash
            )
            VALUES (
                gen_random_uuid(), :object_type,
                CAST(:object_id AS UUID), :action,
                CAST(:before_state AS JSONB),
                CAST(:after_state AS JSONB),
                CAST(:actor_id AS UUID),
                :actor_ip, :user_agent, :reason,
                :occurred_at, :prev_hash, :record_hash
            )
            RETURNING event_uuid
        """),
        {
            **payload,
            "before_state": json.dumps(payload["before_state"], ensure_ascii=False),
            "after_state": json.dumps(payload["after_state"], ensure_ascii=False),
        },
    )

    await db.commit()
    return str(result.scalar_one())
```

### 3.6 감사조회 API

```python
# app/routers/audit.py
from fastapi import APIRouter, Depends, Query
from sqlalchemy import text

from app.core.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/api/audit")


@router.get("/events")
async def get_audit_events(
    object_type: str | None = Query(None),
    object_id: str | None = Query(None),
    actor_id: str | None = Query(None),
    start_date: str | None = Query(None),
    end_date: str | None = Query(None),
    limit: int = Query(50, le=200),
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_ADMIN", "AUDITOR"}:
        return {"detail": "Not authorized"}

    result = await db.execute(
        text("""
            SELECT
                event_uuid,
                object_type,
                object_id,
                action,
                before_state,
                after_state,
                actor_id,
                actor_ip,
                reason,
                occurred_at,
                prev_hash,
                record_hash
            FROM audit_events
            WHERE (:object_type IS NULL OR object_type = :object_type)
              AND (:object_id IS NULL OR object_id = CAST(:object_id AS UUID))
              AND (:actor_id IS NULL OR actor_id = CAST(:actor_id AS UUID))
              AND (:start_date IS NULL OR occurred_at >= :start_date)
              AND (:end_date IS NULL OR occurred_at <= :end_date)
            ORDER BY occurred_at DESC, audit_id DESC
            LIMIT :limit
        """),
        {
            "object_type": object_type,
            "object_id": object_id,
            "actor_id": actor_id,
            "start_date": start_date,
            "end_date": end_date,
            "limit": limit,
        },
    )

    return [dict(row._mapping) for row in result]
```

***

## ④ DSS 기반 PAdES PDF 전자서명 구현

### 4.1 DSS 서비스 구성

DSS는 REST 및 SOAP WebService로 서명 생성, digest 생성, 서명값 결합, 검증 기능을 제공합니다.  공식 GitHub 저장소에서도 PAdES를 포함한 전자서명 생성·확장·검증 기능을 제공합니다. 

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

### 4.2 DSS 클라이언트

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

### 4.3 전자서명 라우터

```python
# app/routers/signature.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user
from app.services.dss_client import sign_pdf_with_pades, validate_signed_pdf

router = APIRouter(prefix="/api/signatures")


class SignDocumentRequest(BaseModel):
    document_version_id: str
    signature_meaning: str  # REVIEW | APPROVAL | RESPONSIBILITY
    reason: str


@router.post("/pades")
async def sign_document(
    body: SignDocumentRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_REVIEWER", "QA_APPROVER"}:
        raise HTTPException(status_code=403, detail="Signing role required")

    if body.signature_meaning not in {"REVIEW", "APPROVAL", "RESPONSIBILITY"}:
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

***

## ⑤ FastAPI 기반 21 CFR Part 11 전자서명 플로우

### 5.1 플로우 설계

```text
[문서 Draft]
     │
     ▼
[작성자 제출]
 action = SUBMIT
     │
     ▼
[검토자 검토]
 action = REVIEW
     │
     ├── 반려 → 작성자 수정
     │
     ▼
[승인자 PAdES 서명]
 action = SIGN
     │
     ▼
[DSS 서명 검증]
 signature_valid = true
     │
     ▼
[문서 승인 완료]
 status = APPROVED
     │
     ▼
[유효일 도래 시 배포]
 action = DEPLOY
     │
     ▼
[구버전 Superseded 처리]
```

### 5.2 상태 전이 규칙

| 현재 상태 | 허용 행위 | 다음 상태 | 감사기록 |
|---|---|---|---|
| DRAFT | 제출 | IN_REVIEW | SUBMIT |
| IN_REVIEW | 승인 서명 | APPROVED | SIGN |
| IN_REVIEW | 반려 | REJECTED | REJECT |
| APPROVED | 배포 | EFFECTIVE | DEPLOY |
| EFFECTIVE | 신규 버전 생성 | SUPERSEDED | CREATE_VERSION |

### 5.3 승인 워크플로 API

```python
# app/routers/approval.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user
from app.services.dss_client import sign_pdf_with_pades

router = APIRouter(prefix="/api/approvals")


class SubmitApprovalRequest(BaseModel):
    document_version_id: str
    approver_id: str
    reason: str


@router.post("/submit")
async def submit_for_approval(
    body: SubmitApprovalRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    before = await get_document_version_state(
        db=db,
        document_version_id=body.document_version_id,
    )

    if before["status"] != "DRAFT":
        raise HTTPException(status_code=400, detail="Only DRAFT can be submitted")

    await update_document_version_status(
        db=db,
        document_version_id=body.document_version_id,
        status="IN_REVIEW",
    )

    after = {**before, "status": "IN_REVIEW"}

    await write_audit(
        db=db,
        object_type="document_version",
        object_id=body.document_version_id,
        action="SUBMIT",
        before_state=before,
        after_state=after,
        actor_id=current_user.user_id,
        request=request,
        reason=body.reason,
    )

    return {"status": "IN_REVIEW"}


@router.post("/sign")
async def approve_with_signature(
    document_version_id: str,
    signature_meaning: str,
    reason: str,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    before = await get_document_version_state(
        db=db,
        document_version_id=document_version_id,
    )

    if before["status"] != "IN_REVIEW":
        raise HTTPException(status_code=400, detail="Document is not in review")

    pdf_bytes = await get_document_pdf(
        db=db,
        document_version_id=document_version_id,
    )

    signed_pdf = await sign_pdf_with_pades(
        pdf_bytes=pdf_bytes,
        certificate_alias=current_user.certificate_alias,
        keystore_password=current_user.keystore_password,
        signature_meaning=signature_meaning,
    )

    await save_signed_pdf(
        db=db,
        document_version_id=document_version_id,
        pdf_bytes=signed_pdf,
    )

    await update_document_version_status(
        db=db,
        document_version_id=document_version_id,
        status="APPROVED",
    )

    after = {**before, "status": "APPROVED", "signed": True}

    await write_audit(
        db=db,
        object_type="document_version",
        object_id=document_version_id,
        action="SIGN",
        before_state=before,
        after_state=after,
        actor_id=current_user.user_id,
        request=request,
        reason=reason,
    )

    return {"status": "APPROVED"}
```

### 5.4 Part 11 통제 항목

| 요구사항 | 구현 방식 |
|---|---|
| 고유 사용자 식별 | Keycloak OIDC 사용자 ID |
| 접근통제 | 역할 기반 RBAC |
| 전자서명 연결 | 서명자·시각·서명의미를 기록에 연결 |
| 감사추적 | append-only `audit_events` |
| 기록 무결성 | SHA-256 해시 체인 |
| 원본 보호 | MinIO WORM 또는 Nextcloud 버전관리 |
| 변경통제 | 상태 전이 규칙 및 승인 필요 |

***

## ⑥ Odoo와 Nextcloud 연동 문서관리 아키텍처

### 6.1 역할 분리

```text
[Odoo]
  품질기록·CAPA·NC·생산·구매·DHR 운영기록
        │
        ▼
[FastAPI eQMS Core]
  문서승인·버전통제·감사추적·전자서명·RAG
        │
        ▼
[Nextcloud]
  SOP·절차서·기술문서·서명 PDF 원본 저장
```

Odoo와 Nextcloud를 연결하는 문서 허브 모듈은 WebDAV를 통해 Odoo 비즈니스 레코드와 Nextcloud 문서를 연결하며, 업로드·미리보기·승인·추적 기능을 제공합니다.  일부 연동 솔루션은 Nextcloud의 WebDAV API를 기반으로 주기 동기화 방식을 사용합니다. 

### 6.2 권장 아키텍처: FastAPI 중계형

```text
[Odoo]
   │ CAPA / NC / DHR Record
   ▼
[FastAPI eQMS]
   │ 문서 메타데이터 생성
   │ 승인 워크플로 실행
   │ 감사추적 기록
   │ 전자서명 요청
   ▼
[Nextcloud WebDAV]
   │ 원본 PDF 저장
   │ 버전관리
   ▼
[MinIO WORM]
   │ 규제 원본·서명 PDF 장기보존
```

**권장 이유**

- Odoo와 Nextcloud가 직접 통신하지 않아 감사추적 누락이 줄어듭니다.
- 문서 업로드·다운로드·승인·서명이 모두 eQMS 감사추적에 기록됩니다.
- Nextcloud 권한과 eQMS 권한을 단일 정책으로 관리할 수 있습니다.
- RAG 색인 대상을 승인 완료 문서로 제한하기 쉽습니다.

### 6.3 폴더 구조

```text
/GMP/
 ├── SOP/
 │    └── SOP-QA-001/
 │         ├── v1.0_Draft.pdf
 │         ├── v1.0_Approved.pdf
 │         └── v2.0_Draft.pdf
 ├── DMR/
 │    └── MDF-DEV-001/
 ├── CAPA/
 │    └── CAPA-2026-001/
 └── DesignFile/
      └── DF-PRJ-001/
```

### 6.4 연동 시퀀스

```text
1. Odoo CAPA 생성
2. Odoo → FastAPI: CAPA 문서 등록 요청
3. FastAPI → PostgreSQL: 문서 메타데이터 저장
4. FastAPI → Nextcloud: 원본 PDF 업로드
5. FastAPI → PostgreSQL: 파일 해시·저장 위치 기록
6. 검토자 → FastAPI: 검토 요청
7. 승인자 → FastAPI: DSS PAdES 서명
8. FastAPI → Nextcloud: 서명 PDF 저장
9. FastAPI → PostgreSQL: 감사추적 기록
10. FastAPI → Qdrant: 승인 문서 색인
```

***

## ⑦ CSV 검증용 IQ·OQ·PQ 문서 템플릿

CSV는 위험 기반 검증 생애주기로, URS부터 위험평가, IQ/OQ/PQ, 변경통제, 감사추적, 기록보존까지 연결해야 합니다.  IQ는 올바른 설치·환경·버전 확인, OQ는 기능·경계조건·오류조건 검증, PQ는 실제 사용자·실제 데이터·실제 업무 흐름 검증에 초점을 둡니다. [casrai](https://casrai.org/guides/computer-system-validation-csv-gamp-5-iq-oq-pq)

### 7.1 공통 문서 구조

```markdown
# [시스템명] IQ/OQ/PQ 검증 프로토콜

## 1. 문서 정보
- 문서번호: V-EQMS-IQOQPQ-001
- 버전: 1.0
- 시스템명: Medical eQMS
- 검증 범위: 문서관리, 감사추적, 전자서명, RAG 검색
- 작성자:
- 검토자:
- 승인자:
- 승인일:

## 2. 목적
본 프로토콜은 Medical eQMS가 승인된 URS 및 위험통제 기준에 따라
설치·운영·성능 요구를 충족함을 입증하기 위한 검증 절차를 정의한다.

## 3. 범위
- 포함: 문서등록, 버전관리, 승인, 감사추적, 전자서명, RAG 검색
- 제외: CAPA, 교육, 설계추적성, ERP 정산 연동

## 4. 역할 및 책임
| 역할 | 책임 |
|---|---|
| QA Owner | URS 승인, 검증 결과 승인 |
| System Owner | 운영환경 승인 |
| IT Validation | IQ/OQ 실행 |
| Business User | PQ 실행 |
| Auditor | 증적 검토 |

## 5. 검증 환경
| 항목 | 내용 |
|---|---|
| 서버 | |
| OS | |
| DB 버전 | |
| API 버전 | |
| DSS 버전 | |
| Qdrant 버전 | |
| Ollama 모델 | |
| 인증서 | |
| 시간동기화 | NTP |

## 6. 사전 조건
- 개발/검증/운영 환경 분리 확인
- 테스트 계정 및 역할 생성
- 샘플 SOP PDF 준비
- 백업 및 롤백 절차 확인

## 7. 편차 처리
- 편차 발생 시 편차번호, 원인, 영향, 조치, 재시험 계획 기록
- 재시험 후 원 테스트와 연결

## 8. 수용 기준
- 모든 High Risk 테스트 통과
- 모든 URS 항목에 대응 테스트 존재
- 편차 없음 또는 승인된 편차만 존재
- 감사추적 증적 확보
```

### 7.2 IQ 템플릿

```markdown
# Installation Qualification (IQ)

## 목적
시스템이 승인된 사양에 따라 올바르게 설치·구성되었음을 입증한다.

## IQ-001: 서버 및 OS 확인
- 요구사항: URS-INF-001
- 시험 방법: 서버 사양 및 OS 버전 확인
- 기대 결과: 승인된 사양과 일치
- 실제 결과:
- 판정: Pass / Fail
- 증적: 스크린샷, 시스템 정보 출력

## IQ-002: PostgreSQL 설치 및 버전 확인
- 요구사항: URS-INF-002
- 시험 방법: `SELECT version();`
- 기대 결과: PostgreSQL 16 이상
- 실제 결과:
- 판정: Pass / Fail

## IQ-003: 감사추적 테이블 생성 확인
- 요구사항: URS-AT-001
- 시험 방법: `audit_events` 테이블 및 인덱스 확인
- 기대 결과: 테이블·인덱스·트리거 존재
- 실제 결과:
- 판정: Pass / Fail

## IQ-004: MinIO WORM 설정 확인
- 요구사항: URS-STG-001
- 시험 방법: 버킷 정책 및 버전관리 확인
- 기대 결과: 원본 덮어쓰기 방지 설정 확인
- 실제 결과:
- 판정: Pass / Fail

## IQ-005: DSS 서비스 접속 확인
- 요구사항: URS-SIG-001
- 시험 방법: DSS REST 헬스체크
- 기대 결과: HTTP 200
- 실제 결과:
- 판정: Pass / Fail

## IQ-006: 시간동기화 확인
- 요구사항: URS-AT-004
- 시험 방법: NTP 동기화 상태 확인
- 기대 결과: 서버 간 시간 오차 허용범위 내
- 실제 결과:
- 판정: Pass / Fail
```

### 7.3 OQ 템플릿

```markdown
# Operational Qualification (OQ)

## 목적
시스템 기능이 기능명세 및 URS에 따라 정상·경계·오류 조건에서 작동함을 입증한다.

## OQ-DOC-001: 문서 등록
- 요구사항: URS-DC-001
- 사전조건: QA_ADMIN 계정 로그인
- 시험 절차:
  1. SOP 문서 등록
  2. 문서번호 자동 생성 확인
  3. SHA-256 해시 생성 확인
- 기대 결과: 문서 생성 및 감사기록 1건 생성
- 실제 결과:
- 판정: Pass / Fail
- 증적: API 응답, DB 레코드, 감사기록

## OQ-DOC-002: 신규 버전 생성
- 요구사항: URS-DC-002
- 시험 절차:
  1. 기존 승인 문서에 신규 버전 등록
  2. 구버전 상태 확인
- 기대 결과: 구버전 SUPERSEDED, 신규버전 DRAFT
- 실제 결과:
- 판정: Pass / Fail

## OQ-AT-001: 감사추적 생성
- 요구사항: URS-AT-001
- 시험 절차:
  1. 문서 생성
  2. 문서 수정
  3. 감사기록 조회
- 기대 결과: CREATE, UPDATE 기록 존재
- 실제 결과:
- 판정: Pass / Fail

## OQ-AT-002: 감사추적 변경 차단
- 요구사항: URS-AT-002
- 시험 절차:
  1. `UPDATE audit_events` 실행
  2. `DELETE FROM audit_events` 실행
- 기대 결과: 두 작업 모두 차단
- 실제 결과:
- 판정: Pass / Fail

## OQ-SIG-001: PAdES 전자서명
- 요구사항: URS-SIG-001
- 시험 절차:
  1. 승인자 로그인
  2. SOP PDF 서명 요청
  3. DSS 검증 요청
- 기대 결과: 서명 성공 및 검증 성공
- 실제 결과:
- 판정: Pass / Fail

## OQ-SIG-002: 서명 후 변조 탐지
- 요구사항: URS-SIG-002
- 시험 절차:
  1. 서명된 PDF 일부 수정
  2. DSS 검증 실행
- 기대 결과: 검증 실패
- 실제 결과:
- 판정: Pass / Fail

## OQ-RAG-001: 승인 문서만 검색
- 요구사항: URS-RAG-001
- 시험 절차:
  1. DRAFT 문서 업로드
  2. APPROVED 문서 업로드
  3. RAG 질의 실행
- 기대 결과: APPROVED 문서만 검색
- 실제 결과:
- 판정: Pass / Fail

## OQ-RAG-002: 근거 없는 질문 처리
- 요구사항: URS-RAG-002
- 시험 절차:
  1. 내부 문서에 없는 질문 입력
- 기대 결과: “확인된 내부 문서 근거가 없습니다” 응답
- 실제 결과:
- 판정: Pass / Fail
```

### 7.4 PQ 템플릿

```markdown
# Performance Qualification (PQ)

## 목적
실제 품질업무 시나리오에서 시스템이 의도된 용도에 맞게 작동함을 입증한다.

## PQ-001: SOP 개정 전 과정
- 참여자: 문서작성자, 검토자, 승인자, 품질관리자
- 시나리오:
  1. SOP v1.0 등록
  2. 검토자 검토
  3. 승인자 PAdES 서명
  4. 유효일 설정 및 배포
  5. RAG에서 v1.0 검색
  6. v2.0 신규 버전 생성
  7. v1.0 Superseded 처리
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

### 7.5 추적성 매트릭스

| URS ID | 위험도 | 기능명세 | OQ Test | PQ Test | 결과 |
|---|---|---|---|---|---|
| URS-DC-001 | High | 문서등록 | OQ-DOC-001 | PQ-001 |  |
| URS-DC-002 | High | 버전관리 | OQ-DOC-002 | PQ-001 |  |
| URS-AT-001 | High | 감사추적 생성 | OQ-AT-001 | PQ-001 |  |
| URS-AT-002 | High | 감사추적 불변성 | OQ-AT-002 | PQ-001 |  |
| URS-SIG-001 | High | PAdES 서명 | OQ-SIG-001 | PQ-001 |  |
| URS-SIG-002 | High | 변조 탐지 | OQ-SIG-002 | PQ-001 |  |
| URS-RAG-001 | Medium | 승인 문서 검색 | OQ-RAG-001 | PQ-003 |  |
| URS-RAG-002 | Medium | 근거 없는 질문 처리 | OQ-RAG-002 | PQ-003 |  |

추적성 매트릭스는 모든 URS가 테스트와 연결되고, 모든 테스트가 요구사항으로 추적되도록 관리해야 합니다. [beefed](https://beefed.ai/en/eqms-computer-system-validation-gamp5)

***

## ⑧ CAPA·교육·설계추적성 확장

### 8.1 CAPA 모듈

```text
[Nonconformance]
     │
     ▼
[CAPA 생성]
     │
     ▼
[원인분석]
     │
     ▼
[시정·예방조치]
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

```sql
CREATE TABLE capa_records (
    capa_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    capa_no VARCHAR(30) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    source_type VARCHAR(30) NOT NULL,
    source_id UUID,
    root_cause TEXT,
    corrective_action TEXT,
    preventive_action TEXT,
    effectiveness_check TEXT,
    status VARCHAR(30) NOT NULL DEFAULT 'OPEN',
    owner_id UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 8.2 교육 모듈

```sql
CREATE TABLE training_assignments (
    training_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_version_id UUID NOT NULL REFERENCES document_versions(id),
    trainee_id UUID NOT NULL REFERENCES users(user_id),
    assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    due_date DATE,
    completed_at TIMESTAMPTZ,
    status VARCHAR(30) NOT NULL DEFAULT 'ASSIGNED'
);
```

문서 승인 시 다음 로직을 실행합니다.

```python
async def assign_training(db, document_version_id, target_roles):
    users = await get_users_by_roles(db, target_roles)

    for user in users:
        await db.execute(text("""
            INSERT INTO training_assignments
            (document_version_id, trainee_id, due_date)
            VALUES
            (CAST(:document_version_id AS UUID),
             CAST(:trainee_id AS UUID),
             CURRENT_DATE + INTERVAL '14 days')
        """), {
            "document_version_id": document_version_id,
            "trainee_id": user.user_id,
        })
```

### 8.3 설계추적성 모듈

```text
User Need
   │
   ▼
Design Input
   │
   ▼
Design Output
   │
   ▼
Risk Control
   │
   ▼
Verification
   │
   ▼
Validation
   │
   ▼
Design Change
```

```sql
CREATE TABLE design_records (
    record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL,
    record_type VARCHAR(40) NOT NULL,
    title VARCHAR(200) NOT NULL,
    document_version_id UUID REFERENCES document_versions(id),
    status VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE design_traceability (
    trace_id BIGSERIAL PRIMARY KEY,
    source_record_id UUID NOT NULL REFERENCES design_records(record_id),
    target_record_id UUID NOT NULL REFERENCES design_records(record_id),
    relation_type VARCHAR(30) NOT NULL
        CHECK (relation_type IN (
            'TRACES_TO','VERIFIES','VALIDATES','DERIVES_FROM'
        ))
);
```

***

## ⑨ RAG-LLM Compliance Pipeline

### 9.1 파이프라인

```text
[승인 SOP]
     │
     ▼
[문서 파싱]
     │
     ▼
[청킹 + 메타데이터]
     │
     ▼
[임베딩]
     │
     ▼
[Qdrant 저장]
     │
     ▼
[권한 필터 검색]
     │
     ▼
[LLM 답변 생성]
     │
     ▼
[출처 인용 응답]
     │
     ▼
[감사추적 기록]
```

### 9.2 검색 필터

```python
filters = {
    "operator": "AND",
    "conditions": [
        {
            "field": "meta.status",
            "operator": "==",
            "value": "APPROVED",
        },
        {
            "field": "meta.access_roles",
            "operator": "in",
            "value": current_user.roles,
        },
    ],
}
```

### 9.3 응답 정책

- 승인되지 않은 문서는 검색 대상에서 제외합니다.
- 답변에는 문서번호, 제목, 버전, 유효일을 반드시 표시합니다.
- 근거가 없으면 “확인된 내부 문서 근거가 없습니다”라고 응답합니다.
- 질의·검색 문서·응답 요약을 감사추적에 기록합니다.
- 비밀번호, 토큰, 서명 PIN은 로그에서 마스킹합니다.

***

## ⑩ 4주 MVP 완료 기준

| 주차 | 완료 기준 |
|---|---|
| **Week 1** | 감사추적 생성, UPDATE/DELETE 차단, 해시체인 검증 |
| **Week 2** | 문서등록, 버전생성, SHA-256 무결성 확인 |
| **Week 3** | PAdES 서명 생성, 서명 검증, 변조 탐지 |
| **Week 4** | 승인 SOP 10건 색인, 권한 필터 검색, 정확도 평가 |

MVP 완료 후에는 CAPA, 교육, 설계추적성, CSV 패키지를 순차 확장합니다. CSV 문서는 검증계획, URS, 위험평가, 추적성 매트릭스, 시험 프로토콜, 시험증적, 검증요약보고서, SOP, 교육기록을 포함해야 하며, 이는 감사 대응의 기본 패키지입니다. [casrai](https://casrai.org/guides/computer-system-validation-csv-gamp-5-iq-oq-pq)