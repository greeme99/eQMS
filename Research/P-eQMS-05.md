아래는 **MVP 완료 후 확장 단계**를 포함한 종합 개발 가이드입니다. 핵심은 PostgreSQL 트리거 기반 감사추적, FastAPI 미들웨어 통합, DSS PAdES 전자서명, SOP RAG 검색, CSV 패키지를 하나의 검증 가능한 시스템으로 연결하는 것입니다. PostgreSQL은 트리거 함수로 데이터 변경을 감사 테이블에 기록하는 표준 방식을 제공하며, Haystack-Qdrant 조합은 문서 색인과 임베딩 기반 검색 파이프라인을 지원합니다. [docs.haystack.deepset](https://docs.haystack.deepset.ai/docs/qdrant-document-store)

***

## ① MVP 이후 확장 로드맵

| 단계 | 기간 | 확장 대상 | 핵심 산출물 |
|---|---:|---|---|
| **MVP 완료** | 4주 | 감사추적·문서버전·전자서명·RAG | 동작 가능한 최소 eQMS |
| **확장 1** | 2주 | CAPA | NC, CAPA, 원인분석, 효과성 확인 |
| **확장 2** | 2주 | 교육 | 문서개정 기반 교육할당, 이수관리 |
| **확장 3** | 2주 | 설계추적성 | Design File, RTM, V&V 연계 |
| **확장 4** | 3~4주 | CSV 패키지 | VMP, URS, Risk, IQ/OQ/PQ, VSR |

***

## ② 감사추적 PostgreSQL 트리거 전체 코드

### 2.1 설계 원칙

- 감사기록은 **INSERT만 허용**하고 UPDATE·DELETE는 차단합니다.
- 문서·버전·승인·서명 테이블에 트리거를 적용합니다.
- 각 감사기록은 이전 해시와 현재 해시를 연결하는 해시 체인을 갖습니다.
- 애플리케이션 계층은 사용자·IP·User-Agent·사유를 추가하고, DB 트리거는 데이터 변경 자체를 기록합니다.
- PostgreSQL 공식 문서는 트리거 함수로 INSERT·UPDATE·DELETE를 감사 테이블에 기록하는 방식을 제시합니다. 

### 2.2 전체 SQL

```sql
-- 1. 확장 설치
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. 사용자 테이블
CREATE TABLE IF NOT EXISTS users (
    user_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_no  VARCHAR(30) UNIQUE NOT NULL,
    full_name    VARCHAR(100) NOT NULL,
    email        VARCHAR(255) UNIQUE NOT NULL,
    role         VARCHAR(30) NOT NULL,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. 문서 테이블
CREATE TABLE IF NOT EXISTS documents (
    document_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_no          VARCHAR(30) UNIQUE NOT NULL,
    title           VARCHAR(200) NOT NULL,
    doc_type        VARCHAR(30) NOT NULL,
    current_version VARCHAR(20),
    status          VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    owner_id        UUID NOT NULL REFERENCES users(user_id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 4. 문서 버전 테이블
CREATE TABLE IF NOT EXISTS document_versions (
    version_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id      UUID NOT NULL REFERENCES documents(document_id),
    version_no       VARCHAR(20) NOT NULL,
    file_id          UUID,
    status           VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    effective_date   DATE,
    superseded_date  DATE,
    created_by       UUID NOT NULL REFERENCES users(user_id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (document_id, version_no)
);

-- 5. 감사추적 테이블
CREATE TABLE IF NOT EXISTS audit_events (
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

-- 6. 인덱스
CREATE INDEX IF NOT EXISTS idx_audit_object
ON audit_events(object_type, object_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_actor
ON audit_events(actor_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_action
ON audit_events(action, occurred_at DESC);

-- 7. 감사추적 불변성: UPDATE·DELETE 차단
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

-- 8. 공통 해시 계산 함수
CREATE OR REPLACE FUNCTION fn_calculate_audit_hash(
    p_object_type VARCHAR,
    p_object_id UUID,
    p_action VARCHAR,
    p_before JSONB,
    p_after JSONB,
    p_occurred_at TIMESTAMPTZ,
    p_prev_hash CHAR(64)
)
RETURNS CHAR(64)
LANGUAGE plpgsql
AS $$
DECLARE
    v_payload JSONB;
BEGIN
    v_payload := jsonb_build_object(
        'object_type', p_object_type,
        'object_id', p_object_id,
        'action', p_action,
        'before_state', p_before,
        'after_state', p_after,
        'occurred_at', p_occurred_at,
        'prev_hash', p_prev_hash
    );

    RETURN encode(
        digest(v_payload::text, 'sha256'),
        'hex'
    );
END;
$$;

-- 9. 이전 해시 조회 함수
CREATE OR REPLACE FUNCTION fn_get_prev_audit_hash(
    p_object_type VARCHAR,
    p_object_id UUID
)
RETURNS CHAR(64)
LANGUAGE plpgsql
AS $$
DECLARE
    v_hash CHAR(64);
BEGIN
    SELECT record_hash
    INTO v_hash
    FROM audit_events
    WHERE object_type = p_object_type
      AND object_id = p_object_id
    ORDER BY occurred_at DESC, audit_id DESC
    LIMIT 1;

    RETURN v_hash;
END;
$$;

-- 10. 공통 감사기록 삽입 함수
CREATE OR REPLACE FUNCTION fn_insert_audit_event(
    p_object_type VARCHAR,
    p_object_id UUID,
    p_action VARCHAR,
    p_before JSONB,
    p_after JSONB,
    p_actor_id UUID DEFAULT NULL,
    p_actor_ip INET DEFAULT NULL,
    p_user_agent TEXT DEFAULT NULL,
    p_reason TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_uuid UUID;
    v_prev_hash CHAR(64);
    v_occurred_at TIMESTAMPTZ := clock_timestamp();
    v_record_hash CHAR(64);
BEGIN
    v_prev_hash := fn_get_prev_audit_hash(
        p_object_type,
        p_object_id
    );

    v_record_hash := fn_calculate_audit_hash(
        p_object_type,
        p_object_id,
        p_action,
        p_before,
        p_after,
        v_occurred_at,
        v_prev_hash
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
        occurred_at,
        prev_hash,
        record_hash
    )
    VALUES (
        p_object_type,
        p_object_id,
        p_action,
        p_before,
        p_after,
        p_actor_id,
        p_actor_ip,
        p_user_agent,
        p_reason,
        v_occurred_at,
        v_prev_hash,
        v_record_hash
    )
    RETURNING event_uuid
    INTO v_event_uuid;

    RETURN v_event_uuid;
END;
$$;

-- 11. 문서 변경 감사 트리거 함수
CREATE OR REPLACE FUNCTION fn_audit_document_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    v_event_uuid := fn_insert_audit_event(
        p_object_type => 'document',
        p_object_id => COALESCE(NEW.document_id, OLD.document_id),
        p_action => TG_OP,
        p_before => CASE
            WHEN TG_OP = 'INSERT' THEN NULL
            ELSE to_jsonb(OLD)
        END,
        p_after => CASE
            WHEN TG_OP = 'DELETE' THEN NULL
            ELSE to_jsonb(NEW)
        END,
        p_reason => 'Database-level document change'
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 12. 문서 트리거 등록
DROP TRIGGER IF EXISTS trg_documents_audit ON documents;

CREATE TRIGGER trg_documents_audit
AFTER INSERT OR UPDATE OR DELETE ON documents
FOR EACH ROW
EXECUTE FUNCTION fn_audit_document_change();

-- 13. 문서 버전 변경 감사 트리거 함수
CREATE OR REPLACE FUNCTION fn_audit_document_version_change()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_uuid UUID;
BEGIN
    v_event_uuid := fn_insert_audit_event(
        p_object_type => 'document_version',
        p_object_id => COALESCE(NEW.version_id, OLD.version_id),
        p_action => TG_OP,
        p_before => CASE
            WHEN TG_OP = 'INSERT' THEN NULL
            ELSE to_jsonb(OLD)
        END,
        p_after => CASE
            WHEN TG_OP = 'DELETE' THEN NULL
            ELSE to_jsonb(NEW)
        END,
        p_reason => 'Database-level document version change'
    );

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 14. 문서 버전 트리거 등록
DROP TRIGGER IF EXISTS trg_document_versions_audit ON document_versions;

CREATE TRIGGER trg_document_versions_audit
AFTER INSERT OR UPDATE OR DELETE ON document_versions
FOR EACH ROW
EXECUTE FUNCTION fn_audit_document_version_change();
```

### 2.5 감사추적 무결성 검증 쿼리

```sql
-- 해시체인 검증: 각 레코드의 prev_hash가 직전 record_hash와 일치하는지 확인
WITH ordered_audit AS (
    SELECT
        audit_id,
        object_type,
        object_id,
        occurred_at,
        prev_hash,
        record_hash,
        LAG(record_hash) OVER (
            PARTITION BY object_type, object_id
            ORDER BY occurred_at, audit_id
        ) AS expected_prev_hash
    FROM audit_events
)
SELECT
    audit_id,
    object_type,
    object_id,
    occurred_at,
    prev_hash,
    expected_prev_hash,
    CASE
        WHEN prev_hash IS NOT DISTINCT FROM expected_prev_hash
        THEN 'VALID'
        ELSE 'INVALID'
    END AS chain_status
FROM ordered_audit
ORDER BY object_type, object_id, occurred_at;
```

***

## ③ DSS PAdES 전자서명 FastAPI 연동 코드

### 3.1 DSS 서비스 구성

DSS는 REST와 SOAP WebService를 제공하며, PAdES 서명 생성·검증 기능을 지원합니다. 

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

### 3.2 DSS 클라이언트

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

### 3.3 전자서명 라우터

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

***

## ④ FastAPI와 PostgreSQL 미들웨어 통합

### 4.1 DB 설정

```python
# app/core/database.py
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

DATABASE_URL = "postgresql+asyncpg://eqms:eqms@db:5432/eqms"

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
```

### 4.2 감사추적 서비스

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

### 4.3 문서 생성 API 통합

```python
# app/routers/documents.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user

router = APIRouter(prefix="/api/documents")


class DocumentCreateRequest(BaseModel):
    title: str
    doc_type: str
    owner_id: str


@router.post("")
async def create_document(
    body: DocumentCreateRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_ADMIN", "DOC_OWNER"}:
        raise HTTPException(status_code=403, detail="Not authorized")

    document_id = await insert_document(
        db=db,
        title=body.title,
        doc_type=body.doc_type,
        owner_id=body.owner_id,
    )

    after_state = {
        "title": body.title,
        "doc_type": body.doc_type,
        "status": "DRAFT",
        "owner_id": body.owner_id,
    }

    await write_audit(
        db=db,
        object_type="document",
        object_id=document_id,
        action="CREATE",
        before_state=None,
        after_state=after_state,
        actor_id=current_user.user_id,
        request=request,
        reason="SOP document registration",
    )

    return {
        "document_id": document_id,
        "status": "DRAFT",
    }
```

### 4.4 전역 요청 로깅 미들웨어

```python
# app/core/middleware.py
import time
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware


class RequestAuditMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        response = await call_next(request)

        elapsed_ms = round((time.time() - start_time) * 1000, 2)

        request.state.audit_context = {
            "method": request.method,
            "path": request.url.path,
            "status_code": response.status_code,
            "elapsed_ms": elapsed_ms,
            "client_ip": request.client.host if request.client else None,
            "user_agent": request.headers.get("user-agent"),
        }

        return response
```

### 4.5 앱 등록

```python
# app/main.py
from fastapi import FastAPI

from app.core.middleware import RequestAuditMiddleware
from app.routers import documents, signature, audit

app = FastAPI(
    title="Medical eQMS",
    version="0.1.0",
)

app.add_middleware(RequestAuditMiddleware)

app.include_router(documents.router)
app.include_router(signature.router)
app.include_router(audit.router)
```

***

## ⑤ SOP RAG 검색 파이프라인 구현

### 5.1 설치

```bash
pip install haystack-ai qdrant-haystack sentence-transformers pypdf
```

Haystack의 Qdrant 통합은 `QdrantDocumentStore`, `QdrantEmbeddingRetriever`, 문서 임베더·텍스트 임베더를 제공합니다. [docs.haystack.deepset](https://docs.haystack.deepset.ai/docs/qdrant-document-store)

### 5.2 색인 파이프라인

```python
# rag/indexing_pipeline.py
from haystack import Pipeline
from haystack.components.converters import PyPDFToDocument
from haystack.components.preprocessors import DocumentCleaner, DocumentSplitter
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack.components.writers import DocumentWriter
from haystack_integrations.document_stores.qdrant import QdrantDocumentStore

document_store = QdrantDocumentStore(
    url="http://qdrant:6333",
    index="approved_sop",
    embedding_dim=384,
    recreate_index=False,
    return_embedding=True,
)

indexing_pipeline = Pipeline()

indexing_pipeline.add_component("pdf_converter", PyPDFToDocument())
indexing_pipeline.add_component("cleaner", DocumentCleaner())
indexing_pipeline.add_component(
    "splitter",
    DocumentSplitter(
        split_by="word",
        split_length=300,
        split_overlap=50,
    ),
)
indexing_pipeline.add_component(
    "document_embedder",
    SentenceTransformersDocumentEmbedder(
        model="BAAI/bge-small-en-v1.5",
        meta_fields_to_embed=[
            "doc_no",
            "title",
            "version",
            "status",
            "effective_date",
            "owner_department",
            "access_roles",
        ],
    ),
)
indexing_pipeline.add_component(
    "writer",
    DocumentWriter(document_store=document_store),
)

indexing_pipeline.connect("pdf_converter", "cleaner")
indexing_pipeline.connect("cleaner", "splitter")
indexing_pipeline.connect("splitter", "document_embedder")
indexing_pipeline.connect("document_embedder", "writer")
```

### 5.3 문서 색인 실행

```python
# rag/index_documents.py
from pathlib import Path

from rag.indexing_pipeline import indexing_pipeline

SOP_DIRECTORY = Path("./data/approved_sop")

pdf_files = [
    str(path)
    for path in SOP_DIRECTORY.glob("*.pdf")
]

result = indexing_pipeline.run(
    {"pdf_converter": {"sources": pdf_files}}
)

print(f"Indexed documents: {result['writer']['documents_written']}")
```

### 5.4 질의 파이프라인

```python
# rag/query_pipeline.py
from haystack import Pipeline
from haystack.components.builders import PromptBuilder
from haystack.components.embedders import SentenceTransformersTextEmbedder
from haystack_integrations.components.retrievers.qdrant import (
    QdrantEmbeddingRetriever,
)
from haystack_integrations.components.generators.ollama import (
    OllamaChatGenerator,
)

from rag.indexing_pipeline import document_store

template = """
당신은 의료기기 제조사의 품질·GMP 문서 검색 비서입니다.

규칙:
1. 제공된 내부 문서 근거만 사용합니다.
2. 근거가 없으면 "확인된 내부 문서 근거가 없습니다"라고 답합니다.
3. 문서번호, 제목, 버전, 유효일을 반드시 인용합니다.
4. 최종 판단과 승인은 품질담당자가 수행해야 합니다.

문서 근거:
{% for doc in documents %}
- 문서번호: {{ doc.meta.doc_no }}
- 제목: {{ doc.meta.title }}
- 버전: {{ doc.meta.version }}
- 유효일: {{ doc.meta.effective_date }}
- 내용: {{ doc.content }}
{% endfor %}

질문: {{ question }}
"""

query_pipeline = Pipeline()

query_pipeline.add_component(
    "text_embedder",
    SentenceTransformersTextEmbedder(
        model="BAAI/bge-small-en-v1.5",
    ),
)

query_pipeline.add_component(
    "retriever",
    QdrantEmbeddingRetriever(
        document_store=document_store,
        top_k=5,
    ),
)

query_pipeline.add_component(
    "prompt_builder",
    PromptBuilder(template=template),
)

query_pipeline.add_component(
    "generator",
    OllamaChatGenerator(
        model="llama3.1:8b",
        url="http://ollama:11434",
    ),
)

query_pipeline.connect(
    "text_embedder.embedding",
    "retriever.query_embedding",
)

query_pipeline.connect(
    "retriever.documents",
    "prompt_builder.documents",
)

query_pipeline.connect(
    "prompt_builder",
    "generator",
)
```

### 5.5 RAG API

```python
# app/routers/rag.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit
from app.core.database import get_db
from app.core.security import get_current_user
from rag.query_pipeline import query_pipeline

router = APIRouter(prefix="/api/rag")


class RagQuestionRequest(BaseModel):
    question: str


@router.post("/ask")
async def ask_sop_question(
    body: RagQuestionRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
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

    result = query_pipeline.run(
        {
            "text_embedder": {"text": body.question},
            "retriever": {"filters": filters},
            "prompt_builder": {"question": body.question},
        }
    )

    retrieved_documents = result["retriever"]["documents"]
    answer = result["generator"]["replies"][0].content

    sources = [
        {
            "doc_no": doc.meta.get("doc_no"),
            "title": doc.meta.get("title"),
            "version": doc.meta.get("version"),
            "effective_date": doc.meta.get("effective_date"),
            "score": doc.score,
        }
        for doc in retrieved_documents
    ]

    await write_audit(
        db=db,
        object_type="rag_query",
        object_id=current_user.user_id,
        action="READ",
        before_state=None,
        after_state={
            "question": body.question,
            "retrieved_documents": sources,
            "answer_summary": answer[:500],
        },
        actor_id=current_user.user_id,
        request=request,
        reason="Approved SOP RAG query",
    )

    return {
        "answer": answer,
        "sources": sources,
    }
```

Haystack 문서는 문서 임베더로 색인용 벡터를, 텍스트 임베더로 질의 벡터를 생성하고, Qdrant Retriever가 두 벡터를 비교해 문서를 검색하는 구조를 제시합니다. [docs.haystack.deepset](https://docs.haystack.deepset.ai/docs/2.21/qdrantembeddingretriever)

***

## ⑥ CSV 검증 패키지 작성 방법

### 6.1 CSV 패키지 구성

| 문서 | 목적 | 작성 시점 |
|---|---|---|
| **Validation Master Plan(VMP)** | 검증 범위·역할·방법 정의 | 프로젝트 시작 |
| **URS** | 사용자 요구사항 정의 | 요구사항 확정 시 |
| **Risk Assessment** | 기능별 위험도·통제 정의 | URS 이후 |
| **Traceability Matrix** | URS-위험-테스트 연결 | 테스트 설계 시 |
| **IQ Protocol** | 설치·환경·구성 검증 | 설치 전 |
| **OQ Protocol** | 기능·경계·오류조건 검증 | 개발 완료 후 |
| **PQ Protocol** | 실제 업무 시나리오 검증 | 운영 전 |
| **Test Evidence** | 실행결과·스크린샷·로그 | 테스트 실행 시 |
| **Deviation Log** | 편차·원인·조치·재시험 | 편차 발생 시 |
| **Validation Summary Report(VSR)** | 검증 결과·잔여리스크·운영승인 | 검증 완료 후 |
| **SOP** | 시스템 운영·백업·장애·변경절차 | 운영 전 |
| **Training Record** | 사용자 교육·이수 증적 | 운영 전 |

CSV는 위험 기반 검증 생애주기로, URS부터 위험평가, IQ/OQ/PQ, 변경통제, 감사추적, 기록보존까지 연결해야 합니다. 

### 6.2 Validation Master Plan 템플릿

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
본 계획은 Medical eQMS가 승인된 요구사항과 규제 요구를 충족함을
검증하기 위한 전략, 범위, 역할, 수용기준을 정의한다.

## 3. 시스템 개요
- 시스템명:
- 시스템 목적:
- 주요 모듈:
- 사용자:
- 배포 형태: On-Premise
- GAMP 분류: Category 4 또는 Category 5

## 4. 검증 범위
- 포함: 문서관리, 버전관리, 감사추적, 전자서명, RAG 검색
- 제외: CAPA, 교육, 설계추적성, ERP 재무연동

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

## 8. 수용기준
- High Risk 테스트 100% 통과
- 모든 URS에 대응 테스트 존재
- 편차 없음 또는 승인된 편차만 존재
- 감사추적 증적 완전성 확보
```

### 6.3 URS 템플릿

```markdown
# User Requirements Specification (URS)

## 1. 문서 정보
- 문서번호: URS-EQMS-001
- 버전: 1.0
- 작성자:
- 승인자:

## 2. 요구사항 분류
- FR: Functional Requirement
- NFR: Non-Functional Requirement
- CR: Compliance Requirement
- SR: Security Requirement

## 3. 요구사항 목록

| ID | 분류 | 요구사항 | 수용기준 | 위험도 | 검증방법 |
|---|---|---|---|---|---|
| URS-DC-001 | FR | 사용자는 SOP를 등록할 수 있다 | 문서번호·제목·유형·소유자 저장 | High | OQ |
| URS-DC-002 | FR | 사용자는 신규 버전을 생성할 수 있다 | 구버전은 SUPERSEDED 처리 | High | OQ |
| URS-AT-001 | CR | 모든 생성·수정·승인 행위는 감사추적된다 | 감사기록 생성 | High | OQ |
| URS-AT-002 | CR | 감사기록은 수정·삭제될 수 없다 | UPDATE/DELETE 차단 | High | OQ |
| URS-SIG-001 | CR | 승인자는 PAdES 전자서명을 수행한다 | 서명 성공 및 검증 성공 | High | OQ |
| URS-SIG-002 | CR | 서명 후 원문 변경은 탐지된다 | 변조 시 검증 실패 | High | OQ |
| URS-RAG-001 | FR | 사용자는 승인 SOP를 검색할 수 있다 | 승인 문서만 검색 | Medium | OQ |
| URS-RAG-002 | FR | 근거 없는 질문에는 근거 없음을 응답한다 | 환각 방지 응답 | Medium | OQ |
```

### 6.4 위험평가 템플릿

| Risk ID | 기능 | 위험 | 영향 | 심각도 | 발생가능성 | 위험도 | 통제 | 검증 |
|---|---|---|---|---:|---:|---|---|---|
| R-001 | 감사추적 | 감사기록 삭제 | 규제 기록 손실 | 5 | 2 | High | append-only 트리거 | OQ-AT-002 |
| R-002 | 전자서명 | 무단 서명 | 무효 승인 | 5 | 2 | High | RBAC + 인증서 | OQ-SIG-001 |
| R-003 | 문서버전 | 구버전 덮어쓰기 | 이력 상실 | 4 | 3 | High | 버전 불변 설계 | OQ-DOC-002 |
| R-004 | RAG | 비승인 문서 검색 | 잘못된 품질 판단 | 4 | 3 | High | status 필터 | OQ-RAG-001 |
| R-005 | RAG | 근거 없는 답변 | 오해 유발 | 4 | 3 | High | 근거 없음 정책 | OQ-RAG-002 |

### 6.5 추적성 매트릭스 템플릿

| URS ID | 위험 ID | 기능명세 | OQ Test | PQ Test | 결과 | 승인자 |
|---|---|---|---|---|---|---|
| URS-DC-001 | R-003 | 문서등록 | OQ-DOC-001 | PQ-001 |  |  |
| URS-DC-002 | R-003 | 버전관리 | OQ-DOC-002 | PQ-001 |  |  |
| URS-AT-001 | R-001 | 감사추적 생성 | OQ-AT-001 | PQ-001 |  |  |
| URS-AT-002 | R-001 | 감사추적 불변성 | OQ-AT-002 | PQ-001 |  |  |
| URS-SIG-001 | R-002 | PAdES 서명 | OQ-SIG-001 | PQ-001 |  |  |
| URS-SIG-002 | R-002 | 변조 탐지 | OQ-SIG-002 | PQ-001 |  |  |
| URS-RAG-001 | R-004 | 승인 문서 검색 | OQ-RAG-001 | PQ-003 |  |  |
| URS-RAG-002 | R-005 | 근거 없는 질문 처리 | OQ-RAG-002 | PQ-003 |  |  |

### 6.6 IQ 프로토콜 템플릿

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

### 6.7 OQ 프로토콜 템플릿

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

### 6.8 PQ 프로토콜 템플릿

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

### 6.9 Validation Summary Report 템플릿

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

## 6. 운영 전환 승인
- QA Owner 승인:
- System Owner 승인:
- 승인일:
- 운영 전환일:
```

***

## ⑦ 운영 SOP 및 교육기록

### 7.1 운영 SOP 항목

| SOP | 내용 |
|---|---|
| **SOP-EQMS-001** | 문서 등록·개정·승인·배포 절차 |
| **SOP-EQMS-002** | 감사추적 조회·검증 절차 |
| **SOP-EQMS-003** | 전자서명 발급·사용·폐기 절차 |
| **SOP-EQMS-004** | RAG 검색·출처확인·환각 대응 절차 |
| **SOP-EQMS-005** | 백업·복구·장애 대응 절차 |
| **SOP-EQMS-006** | 변경관리·CSV 재검증 절차 |

### 7.2 교육기록 템플릿

| 교육 ID | 대상자 | 교육문서 | 교육일 | 이수일 | 평가 | 승인자 |
|---|---|---|---|---|---|---|
| TRN-001 |  | SOP-EQMS-001 |  |  |  |  |
| TRN-002 |  | SOP-EQMS-002 |  |  |  |  |
| TRN-003 |  | SOP-EQMS-003 |  |  |  |  |

***

## ⑧ MVP 완료 후 확장 우선순위

| 우선순위 | 모듈 | 이유 |
|---:|---|---|
| 1 | **CAPA** | NC→CAPA→효과성 확인이 품질시스템의 핵심 |
| 2 | **교육** | 문서개정 시 교육할당 자동화 필요 |
| 3 | **설계추적성** | Design File·RTM으로 규제 대응 강화 |
| 4 | **CSV 패키지** | 감사 대응 및 운영전환 승인 |
| 5 | **Odoo·Nextcloud 연동** | 품질기록과 문서 원본의 통합 |

이 구조로 개발하면 **감사추적은 DB 트리거와 애플리케이션 로그의 이중 기록**, **전자서명은 DSS PAdES와 감사추적 연동**, **RAG는 승인 문서만 검색하고 출처를 인용**, **CSV는 URS부터 VSR까지 추적성으로 연결**되는 규제 준수형 eQMS를 단계적으로 완성할 수 있습니다. [docs.haystack.deepset](https://docs.haystack.deepset.ai/docs/qdrant-document-store)