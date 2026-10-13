아래는 요청하신 **9개 항목을 하나의 개발 실행 가이드**로 통합한 문서입니다. 기준은 “Phase 1 MVP → Part 11 통제 → RAG·LLM 파일럿” 순서이며, 각 단계는 2주 스프린트 단위로 개발·검증 산출물을 분리했습니다. DSS는 REST 기반 PAdES 서명·검증 기능을 제공하며, Odoo-Nextcloud 연동은 WebDAV 기반 문서 허브 또는 주기 동기화 방식으로 구성할 수 있습니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/signature-rest)

***

## ① Phase 1 백로그: 2주 스프린트 구성

### Sprint 0: 준비 및 기준 확정 (2주)

| 항목 | 작업 | 산출물 | 완료 기준 |
|---|---|---|---|
| 0-1 | 시스템 범위·역할 정의 | Scope Statement, RACI | 품질·IT·개발 책임자 승인 |
| 0-2 | URS 초안 작성 | URS-v0.1 | 문서등록·버전·승인·감사추적·배포 요구 포함 |
| 0-3 | 위험평가 | Risk Assessment Matrix | 고위험 기능 식별 및 통제 정의 |
| 0-4 | 환경 구성 | dev/staging/prod 분리 | 로컬 개발 환경과 사내 AX 서버 분리 |
| 0-5 | 저장소·CI 구성 | Git, Docker Compose, CI | 코드·마이그레이션·테스트 자동 실행 |

### Sprint 1: 문서등록 및 버전생성 (2주)

| ID | User Story | 수용기준 |
|---|---|---|
| 1-1 | 품질담당자는 SOP를 등록할 수 있다 | 문서번호, 제목, 문서유형, 소유부서, 유효일 입력 |
| 1-2 | 시스템은 문서번호를 자동 부여한다 | 중복 없음, 규칙 기반 생성 |
| 1-3 | 품질담당자는 신규 버전을 생성할 수 있다 | 기존 버전은 Superseded, 신규 버전은 Draft |
| 1-4 | 시스템은 파일 해시를 생성한다 | SHA-256 저장, 재계산 시 일치 |
| 1-5 | 관리자는 문서 현황을 조회한다 | 상태별 필터, 버전 이력 조회 |

**API 예시**

```http
POST /api/documents
POST /api/documents/{document_id}/versions
GET  /api/documents/{document_id}
GET  /api/documents/{document_id}/versions
```

### Sprint 2: 승인요청 및 감사추적 (2주)

| ID | User Story | 수용기준 |
|---|---|---|
| 2-1 | 작성자는 승인요청을 생성한다 | 승인자·역할·기한 지정 |
| 2-2 | 승인자는 승인 또는 반려한다 | 사유 필수, 상태 변경 기록 |
| 2-3 | 시스템은 모든 행위를 감사추적한다 | 생성·수정·조회·승인·반려 기록 |
| 2-4 | 감사추적은 수정·삭제가 불가능하다 | DB Rule 또는 트리거로 차단 |
| 2-5 | 감사담당자는 이력을 조회한다 | 객체·사용자·기간별 검색 |

### Sprint 3: 배포 및 교육 알림 (2주)

| ID | User Story | 수용기준 |
|---|---|---|
| 3-1 | 승인 완료 문서를 배포한다 | 유효일 시작, 구버전 회수 |
| 3-2 | 관련 부서에 변경 알림을 발송한다 | 이메일 또는 사내 메신저 연동 |
| 3-3 | 교육 대상자를 지정한다 | 문서유형·역할 기반 자동 지정 |
| 3-4 | 배포 이력을 조회한다 | 배포일·대상·확인 여부 |
| 3-5 | 문서 개정 시 구버전 접근을 제한한다 | 권한별 조회 통제 |

### Sprint 4: CSV 준비 및 MVP 검증 (2주)

| ID | 작업 | 산출물 |
|---|---|---|
| 4-1 | URS를 확정한다 | URS-v1.0 |
| 4-2 | 기능 위험도를 평가한다 | Risk Control Matrix |
| 4-3 | IQ/OQ 테스트케이스를 작성한다 | Test Protocol |
| 4-4 | 감사추적·버전·승인 테스트를 수행한다 | Test Evidence |
| 4-5 | MVP 검증보고서를 작성한다 | MVP Validation Summary |

***

## ② 감사추적 PoC: 1주 내 동작 확인

### 목표

PostgreSQL `audit_events` 테이블과 FastAPI 미들웨어를 이용해, 문서 생성·수정·승인 행위가 **수정·삭제 불가능한 append-only 로그**로 기록되는지 확인합니다. 21 CFR Part 11은 전자기록 생성·수정·삭제에 대한 안전하고 시간 기록된 감사추적을 요구하며, 이전 기록이 가려지지 않아야 합니다. 

### 1주 개발 계획

| Day | 작업 | 산출물 |
|---:|---|---|
| 1 | PostgreSQL 스키마·Rule 생성 | `audit_events` 테이블 |
| 2 | SQLAlchemy 모델·DB 세션 구성 | ORM 모델 |
| 3 | FastAPI 감사추적 서비스 구현 | `audit_service.py` |
| 4 | 문서 API에 감사추적 연결 | 문서 생성·수정 API |
| 5 | 무결성 테스트 | UPDATE/DELETE 차단, 해시 검증 |
| 6 | 감사조회 API | 기간·객체·사용자 필터 |
| 7 | PoC 보고서 | 테스트 결과·제한사항 |

### PostgreSQL 스키마

```sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_no VARCHAR(30) UNIQUE NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    role VARCHAR(30) NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE documents (
    document_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doc_no VARCHAR(30) UNIQUE NOT NULL,
    title VARCHAR(200) NOT NULL,
    doc_type VARCHAR(30) NOT NULL,
    current_version VARCHAR(20),
    status VARCHAR(30) NOT NULL DEFAULT 'DRAFT',
    owner_id UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_events (
    audit_id BIGSERIAL PRIMARY KEY,
    event_uuid UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type VARCHAR(50) NOT NULL,
    object_id UUID NOT NULL,
    action VARCHAR(20) NOT NULL CHECK (
        action IN (
            'CREATE','READ','UPDATE','DELETE',
            'SUBMIT','APPROVE','REJECT','SIGN','DEPLOY','EXPORT'
        )
    ),
    before_state JSONB,
    after_state JSONB,
    actor_id UUID NOT NULL REFERENCES users(user_id),
    actor_ip INET,
    user_agent TEXT,
    reason TEXT,
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    prev_hash CHAR(64),
    record_hash CHAR(64) NOT NULL
);

CREATE INDEX idx_audit_object
ON audit_events(object_type, object_id, occurred_at DESC);

CREATE INDEX idx_audit_actor
ON audit_events(actor_id, occurred_at DESC);

CREATE INDEX idx_audit_action
ON audit_events(action, occurred_at DESC);

-- append-only 보장
CREATE RULE audit_events_no_update AS
ON UPDATE TO audit_events DO INSTEAD NOTHING;

CREATE RULE audit_events_no_delete AS
ON DELETE TO audit_events DO INSTEAD NOTHING;
```

### FastAPI 감사추적 구현

```python
# app/core/audit.py
import hashlib
import json
from datetime import datetime, timezone

from fastapi import Request
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

SENSITIVE_KEYS = {"password", "token", "secret", "pin", "private_key"}


def sanitize_state(state: dict | None) -> dict | None:
    if state is None:
        return None

    return {
        key: ("***" if key.lower() in SENSITIVE_KEYS else value)
        for key, value in state.items()
    }


def calculate_hash(payload: dict) -> str:
    canonical = json.dumps(
        payload,
        sort_keys=True,
        ensure_ascii=False,
        separators=(",", ":"),
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


async def write_audit_event(
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
    prev_hash = await get_last_hash(
        db=db,
        object_type=object_type,
        object_id=object_id,
    )

    occurred_at = datetime.now(timezone.utc).isoformat()

    base_payload = {
        "object_type": object_type,
        "object_id": object_id,
        "action": action,
        "before_state": sanitize_state(before_state),
        "after_state": sanitize_state(after_state),
        "actor_id": actor_id,
        "actor_ip": request.client.host if request.client else None,
        "user_agent": request.headers.get("user-agent"),
        "reason": reason,
        "occurred_at": occurred_at,
        "prev_hash": prev_hash,
    }

    record_hash = calculate_hash(base_payload)
    event_uuid = await insert_audit_event(
        db=db,
        payload=base_payload,
        record_hash=record_hash,
    )

    await db.commit()
    return event_uuid


async def get_last_hash(
    db: AsyncSession,
    *,
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


async def insert_audit_event(
    db: AsyncSession,
    *,
    payload: dict,
    record_hash: str,
) -> str:
    result = await db.execute(
        text("""
            INSERT INTO audit_events (
                object_type, object_id, action,
                before_state, after_state,
                actor_id, actor_ip, user_agent,
                reason, occurred_at,
                prev_hash, record_hash
            )
            VALUES (
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
            "before_state": json.dumps(payload["before_state"], ensure_ascii=False),
            "after_state": json.dumps(payload["after_state"], ensure_ascii=False),
        },
    )

    return str(result.scalar_one())
```

### 문서 생성 API 적용

```python
# app/routers/documents.py
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from app.core.audit import write_audit_event
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

    await write_audit_event(
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

    return {"document_id": document_id, "status": "DRAFT"}
```

### 무결성 테스트

```python
# tests/test_audit_integrity.py
import pytest
from sqlalchemy import text


@pytest.mark.asyncio
async def test_audit_update_is_blocked(db_session):
    with pytest.raises(Exception):
        await db_session.execute(
            text("""
                UPDATE audit_events
                SET reason = 'tampered'
                WHERE audit_id = 1
            """)
        )


@pytest.mark.asyncio
async def test_audit_delete_is_blocked(db_session):
    with pytest.raises(Exception):
        await db_session.execute(
            text("""
                DELETE FROM audit_events
                WHERE audit_id = 1
            """)
        )
```

**PoC 통과 기준**

- 문서 생성 시 감사기록 1건 생성
- `UPDATE`, `DELETE` 시도가 차단됨
- `record_hash` 재계산 결과가 저장값과 일치
- 감사조회 API에서 사용자·기간·객체별 검색 가능

***

## ③ DSS 기반 PDF 전자서명 PoC

### 목표

샘플 SOP PDF 1건에 대해 **PAdES 전자서명 생성 → 서명 검증 → 감사추적 기록**까지 수행합니다. DSS는 PAdES·XAdES·CAdES·JAdES 등 전자서명 생성·확장·검증을 지원하며, REST/SOAP WebService와 OpenAPI 문서를 제공합니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/signature-rest)

### DSS 서버 구성

```yaml
# docker-compose.dss.yml
services:
  dss:
    image: esig/dss-demonstrations
    container_name: dss-service
    ports:
      - "8080:8080"
    environment:
      - JAVA_OPTS=-Xmx2g
    restart: unless-stopped
```

DSS 공식 저장소에는 REST 호출 예제를 포함한 데모 프로젝트와 Postman/SOAPUI 프로젝트가 제공됩니다. [github](https://github.com/esig/dss)

### PoC 절차

| 단계 | 작업 | 확인 항목 |
|---:|---|---|
| 1 | 샘플 SOP PDF 준비 | 문서번호·버전·작성자 포함 |
| 2 | DSS REST API로 서명 요청 | PAdES 서명 생성 |
| 3 | 서명된 PDF 저장 | MinIO 또는 Nextcloud 저장 |
| 4 | 서명 검증 API 호출 | 서명 유효성·무결성 확인 |
| 5 | 감사추적 기록 | 서명자·시각·서명의미 기록 |
| 6 | 원문 변조 테스트 | 변조 시 검증 실패 확인 |

### FastAPI DSS 클라이언트

```python
# app/services/dss_client.py
import httpx
from fastapi import HTTPException

DSS_BASE_URL = "http://dss-service:8080"


async def sign_pdf_with_dss(
    *,
    pdf_bytes: bytes,
    certificate_alias: str,
    keystore_password: str,
    signature_meaning: str,
) -> bytes:
    files = {
        "document": ("sop.pdf", pdf_bytes, "application/pdf"),
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


async def validate_pdf_signature(pdf_bytes: bytes) -> dict:
    files = {
        "document": ("signed_sop.pdf", pdf_bytes, "application/pdf"),
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

### 서명 API

```python
# app/routers/signature.py
from fastapi import APIRouter, Depends, HTTPException, Request, UploadFile, File
from pydantic import BaseModel

from app.core.audit import write_audit_event
from app.core.database import get_db
from app.core.security import get_current_user
from app.services.dss_client import sign_pdf_with_dss, validate_pdf_signature

router = APIRouter(prefix="/api/signatures")


class SignRequest(BaseModel):
    document_version_id: str
    signature_meaning: str  # APPROVAL | REVIEW | RESPONSIBILITY


@router.post("/sign")
async def sign_sop(
    body: SignRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if current_user.role not in {"QA_APPROVER", "QA_REVIEWER"}:
        raise HTTPException(status_code=403, detail="Signing role required")

    pdf_bytes = await get_document_pdf(db, body.document_version_id)
    before_state = await get_document_version_state(db, body.document_version_id)

    signed_pdf = await sign_pdf_with_dss(
        pdf_bytes=pdf_bytes,
        certificate_alias=current_user.certificate_alias,
        keystore_password=current_user.keystore_password,
        signature_meaning=body.signature_meaning,
    )

    validation_result = await validate_pdf_signature(signed_pdf)

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
    }

    await write_audit_event(
        db=db,
        object_type="document_version",
        object_id=body.document_version_id,
        action="SIGN",
        before_state=before_state,
        after_state=after_state,
        actor_id=current_user.user_id,
        request=request,
        reason=f"SOP {body.signature_meaning.lower()} signature",
    )

    return {
        "document_version_id": body.document_version_id,
        "signed": True,
        "validation": validation_result,
    }
```

### 검증 포인트

- 서명자 이름, 서명 시각, 서명 의미가 문서와 연결되는지
- 서명 후 PDF 원문이 변경되면 검증이 실패하는지
- 서명 기록이 `audit_events`에 남는지
- 서명된 PDF가 MinIO/Nextcloud에 저장되는지

DSS는 PAdES 서명 생성뿐 아니라 서명 검증, 타임스탬프, 인증서 검증 기능도 REST로 제공합니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/signature-rest)

***

## ④ RAG 파일럿: 승인 SOP 10~20건

### 목표

승인 완료된 SOP 10~20건을 색인한 뒤, 품질담당자 3~5명이 실제 업무 질문을 수행하고 답변 정확도를 평가합니다. Haystack과 Qdrant를 조합하면 문서 파싱·청킹·임베딩·검색·생성 파이프라인을 구성할 수 있습니다. 

### 파일럿 범위

| 항목 | 기준 |
|---|---|
| 대상 문서 | 승인 완료 SOP 10~20건 |
| 문서 유형 | 절차서, 작업표준서, 품질절차서 |
| 사용자 | 품질담당자 3~5명 |
| 평가 질문 | 문서당 5~10개 |
| 평가 기준 | 정확성, 출처일치, 완결성, 환각률 |
| 통과 기준 | 정확성 80% 이상, 환각률 10% 미만 |

### 색인 파이프라인

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
)

pipeline = Pipeline()

pipeline.add_component("pdf_converter", PyPDFToDocument())
pipeline.add_component("cleaner", DocumentCleaner())
pipeline.add_component(
    "splitter",
    DocumentSplitter(
        split_by="word",
        split_length=300,
        split_overlap=50,
    ),
)
pipeline.add_component(
    "embedder",
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
pipeline.add_component("writer", DocumentWriter(document_store=document_store))

pipeline.connect("pdf_converter", "cleaner")
pipeline.connect("cleaner", "splitter")
pipeline.connect("splitter", "embedder")
pipeline.connect("embedder", "writer")
```

### 질의 파이프라인

```python
# rag/query_pipeline.py
from haystack import Pipeline
from haystack.components.embedders import SentenceTransformersTextEmbedder
from haystack.components.builders import PromptBuilder
from haystack_integrations.components.retrievers.qdrant import QdrantEmbeddingRetriever
from haystack_integrations.components.generators.ollama import OllamaChatGenerator

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
    SentenceTransformersTextEmbedder(model="BAAI/bge-small-en-v1.5"),
)

query_pipeline.add_component(
    "retriever",
    QdrantEmbeddingRetriever(document_store=document_store, top_k=5),
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

query_pipeline.connect("text_embedder.embedding", "retriever.query_embedding")
query_pipeline.connect("retriever.documents", "prompt_builder.documents")
query_pipeline.connect("prompt_builder", "generator")
```

### 평가표

| 평가 항목 | 정의 | 측정 방법 |
|---|---|---|
| **정확성** | 답변이 SOP 내용과 일치하는가 | 전문가 3점 척도 |
| **출처일치** | 인용 문서·버전이 실제 근거인가 | 출처 대조 |
| **완결성** | 질문에 필요한 내용이 누락되지 않았는가 | 누락 항목 수 |
| **환각률** | 근거 없는 내용 비율 | 근거 없는 문장 수 / 전체 문장 수 |
| **검색 재현율** | 정답 문서가 Top-5에 포함되는가 | Hit@5 |

***

## ⑤ Phase 1 MVP → Part 11 eQMS 아키텍처

### 전체 아키텍처

```text
[사용자 브라우저]
        │ HTTPS
        ▼
[Nextcloud] ─── SOP 원본 PDF·DOCX 저장
        │ WebDAV / Webhook
        ▼
[FastAPI eQMS Core]
        │
        ├── [PostgreSQL Primary/Standby]
        │      ├── users
        │      ├── documents
        │      ├── document_versions
        │      ├── approvals
        │      └── audit_events
        │
        ├── [MinIO WORM Bucket]
        │      └── 원본 PDF·서명 PDF
        │
        ├── [Keycloak]
        │      └── SSO·MFA·RBAC
        │
        ├── [DSS Service]
        │      └── PAdES 서명·검증
        │
        └── [Haystack + Qdrant + Ollama]
               └── 승인 SOP RAG
```

### DB 스키마 매핑

| 도메인 | 테이블 | 핵심 컬럼 | Part 11 통제 |
|---|---|---|---|
| 사용자 | `users` | user_id, role, is_active | RBAC, 계정 비활성화 |
| 문서 | `documents` | doc_no, title, status, owner_id | 문서번호 유일성 |
| 버전 | `document_versions` | version, file_id, status, effective_date | 버전 불변성 |
| 승인 | `document_approvals` | approver_id, decision, signed_at | 서명자·시각·의미 |
| 파일 | `files` | sha256, storage_path | 무결성 검증 |
| 감사 | `audit_events` | action, before_state, after_state, record_hash | append-only |
| 서명 | `signatures` | signature_id, signer_id, signature_meaning | 서명-기록 연결 |

### 전자서명 워크플로

```text
Draft 문서
   │
   ▼
작성자 제출 (SUBMIT)
   │
   ▼
검토자 검토 (REVIEW)
   │
   ├─ 반려 → 작성자 수정
   │
   ▼
승인자 PAdES 서명 (SIGN)
   │
   ▼
서명 검증 (VALIDATE)
   │
   ▼
문서 승인 완료 (APPROVED)
   │
   ▼
유효일 도래 시 배포 (DEPLOY)
   │
   ▼
구버전 Superseded 처리
```

***

## ⑥ RAG-LLM Compliance Pipeline 설계

### 목적

ISO 13485 및 FDA QMSR 관련 질의에 대해 **사내 승인 문서만 검색**하고, 답변에 출처와 문서 버전을 제시하며, 질의 이력 자체도 감사추적에 남기는 파이프라인입니다. FDA QMSR은 2026년 2월 2일부터 시행되었으며 ISO 13485:2016을 참조합니다. 

### 파이프라인 구성

```text
[질의]
   │
   ▼
[사용자 인증·권한 확인]
   │
   ▼
[질의 전처리]
   │
   ▼
[Qdrant 검색]
   │  필터: status = APPROVED
   │  필터: access_roles ∈ 사용자 역할
   │
   ▼
[출처 검증]
   │  문서번호·버전·유효일 존재 확인
   │
   ▼
[LLM 답변 생성]
   │
   ▼
[출처 인용 포함 응답]
   │
   ▼
[감사추적 기록]
```

### 기술 명세

| 항목 | 설계 |
|---|---|
| 검색 대상 | `status = APPROVED` 문서만 |
| 접근통제 | 사용자 역할과 `access_roles` 매칭 |
| 청킹 | 300단어, 50단어 중복 |
| 임베딩 | BAAI/bge-small-en-v1.5 |
| 벡터DB | Qdrant |
| LLM | Ollama 기반 Llama 3.1 8B |
| 응답 정책 | 근거 없으면 “근거 없음” 응답 |
| 감사기록 | 질의·검색 문서·응답 요약 기록 |
| 금지사항 | 비밀번호·토큰·서명 PIN 로깅 금지 |

### 감사추적 연동

```python
await write_audit_event(
    db=db,
    object_type="rag_query",
    object_id=current_user.user_id,
    action="READ",
    before_state=None,
    after_state={
        "question": body.question,
        "retrieved_documents": [
            {
                "doc_no": doc.meta["doc_no"],
                "version": doc.meta["version"],
                "score": doc.score,
            }
            for doc in retrieved_documents
        ],
        "answer_summary": answer[:500],
    },
    actor_id=current_user.user_id,
    request=request,
    reason="ISO 13485 / QMSR compliance query",
)
```

***

## ⑦ Odoo와 Nextcloud 연동 구조

### 연동 목적

| 시스템 | 역할 |
|---|---|
| **Odoo** | 품질기록, CAPA, 구매, 생산, DHR 운영기록 |
| **Nextcloud** | SOP·절차서·기술문서 원본 저장 및 버전관리 |
| **FastAPI eQMS** | 문서승인, 감사추적, 전자서명, RAG |
| **PostgreSQL** | 규제 기록·감사추적의 단일 진실 소스 |

Odoo와 Nextcloud를 연결하는 문서 허브 모듈은 WebDAV를 통해 Odoo 레코드와 Nextcloud 문서를 연결하고, 업로드·미리보기·승인·추적 기능을 제공합니다.  Nextcloud는 WebDAV API 기반으로 Odoo와 연동되며, 일부 상용 연동 솔루션은 주기 동기화 방식으로 Nextcloud 변경사항을 반영합니다. [apps.odoo](https://apps.odoo.com/apps/modules/19.0/odoo_nextcloud_document_hub)

### 연동 아키텍처

```text
[Odoo]
  ├── CAPA Record
  ├── Nonconformance Record
  ├── Production Order
  └── Quality Check
        │
        │ Record ID + Document Type
        ▼
[FastAPI eQMS]
  ├── 문서 메타데이터
  ├── 승인 워크플로
  ├── 감사추적
  └── 전자서명
        │
        │ WebDAV Upload / Download
        ▼
[Nextcloud]
  ├── /GMP/SOP/
  ├── /GMP/DMR/
  ├── /GMP/CAPA/
  └── /GMP/DesignFile/
```

### 폴더 구조 예시

```text
/GMP/
 ├── SOP/
 │    ├── SOP-QA-001/
 │    │    ├── v1.0_Draft.pdf
 │    │    ├── v1.0_Approved.pdf
 │    │    └── v2.0_Draft.pdf
 ├── DMR/
 │    ├── MDF-DEV-001/
 ├── CAPA/
 │    ├── CAPA-2026-001/
 └── DesignFile/
      ├── DF-PRJ-001/
```

### 연동 방식

| 방식 | 설명 | 장점 | 주의점 |
|---|---|---|---|
| **WebDAV 직접 연동** | FastAPI가 Nextcloud WebDAV로 업로드·다운로드 | 실시간성, 단순 구조 | 네트워크·인증 관리 필요 |
| **Odoo 문서 허브 모듈** | Odoo 레코드와 Nextcloud 문서 연결 | 레코드 단위 권한 유지  [apps.odoo](https://apps.odoo.com/apps/modules/19.0/odoo_nextcloud_document_hub) | 모듈 검증 필요 |
| **주기 동기화** | Nextcloud 변경사항을 주기적으로 Odoo에 반영 | webhook 불가 환경에 적합  [ecfr](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11) | 실시간성 제한 |
| **FastAPI 중계** | Odoo와 Nextcloud가 직접 통신하지 않고 eQMS가 중계 | 감사추적·권한 통제 용이 | 개발 범위 증가 |

### 권장 구조

**FastAPI 중계 방식**을 권장합니다.

```text
Odoo → FastAPI → Nextcloud
Odoo → FastAPI → PostgreSQL Audit Trail
FastAPI → DSS → Signed PDF → Nextcloud
```

이유는 다음과 같습니다.

- 모든 문서 업로드·다운로드·승인·서명이 감사추적에 기록됨
- Nextcloud 권한과 eQMS 권한을 단일 정책으로 관리 가능
- Odoo의 품질기록과 문서 버전의 정합성 유지 가능
- RAG 색인 대상 문서를 승인 완료 상태로 제한 가능

***

## ⑧ 개발 환경 및 저장소 구조

### 저장소 구조

```text
medical-eqms/
├── backend/
│   ├── app/
│   │   ├── core/
│   │   │   ├── config.py
│   │   │   ├── database.py
│   │   │   ├── security.py
│   │   │   └── audit.py
│   │   ├── models/
│   │   ├── schemas/
│   │   ├── routers/
│   │   ├── services/
│   │   └── main.py
│   ├── alembic/
│   ├── tests/
│   └── pyproject.toml
├── rag/
│   ├── indexing_pipeline.py
│   ├── query_pipeline.py
│   └── evaluation/
├── dss/
│   ├── docker-compose.dss.yml
│   └── postman/
├── docs/
│   ├── URS.md
│   ├── Risk_Assessment.md
│   ├── IQ_OQ_PQ.md
│   └── Validation_Report.md
├── docker-compose.yml
└── README.md
```

### Docker Compose 예시

```yaml
version: "3.9"

services:
  api:
    build: ./backend
    ports:
      - "8000:8000"
    environment:
      DATABASE_URL: postgresql+asyncpg://eqms:eqms@db:5432/eqms
      DSS_BASE_URL: http://dss:8080
      QDRANT_URL: http://qdrant:6333
      OLLAMA_URL: http://ollama:11434
    depends_on:
      - db
      - dss
      - qdrant
      - ollama

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: eqms
      POSTGRES_PASSWORD: eqms
      POSTGRES_DB: eqms
    volumes:
      - pgdata:/var/lib/postgresql/data

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    volumes:
      - minio_data:/data

  qdrant:
    image: qdrant/qdrant
    ports:
      - "6333:6333"
    volumes:
      - qdrant_data:/qdrant/storage

  ollama:
    image: ollama/ollama
    ports:
      - "11434:11434"
    volumes:
      - ollama_data:/root/.ollama

  dss:
    image: esig/dss-demonstrations
    ports:
      - "8080:8080"

volumes:
  pgdata:
  minio_data:
  qdrant_data:
  ollama_data:
```

***

## ⑨ 검증 및 운영 전환 체크리스트

| 구분 | 점검 항목 | 통과 기준 |
|---|---|---|
| **문서관리** | 문서번호 중복 없음 | 중복 0건 |
| **버전관리** | 구버전 덮어쓰기 없음 | 모든 버전 이력 보존 |
| **승인** | 승인자·시각·의미 기록 | 100% 기록 |
| **감사추적** | UPDATE/DELETE 차단 | 시도 시 차단 |
| **무결성** | SHA-256 재계산 일치 | 100% 일치 |
| **전자서명** | 서명 후 변조 탐지 | 변조 시 검증 실패 |
| **RAG** | 비승인 문서 미검색 | 승인 문서만 검색 |
| **RAG** | 출처 인용 포함 | 100% 문서번호·버전 표시 |
| **권한** | 역할 외 접근 차단 | 403 반환 |
| **백업** | DB·파일 백업 복구 | 복구 테스트 통과 |
| **CSV** | IQ/OQ/PQ 증적 | 승인 완료 |

***

## ⑩ 다음 4주 실행 계획

| 주차 | 목표 | 핵심 산출물 |
|---|---|---|
| **1주차** | 감사추적 PoC 완성 | `audit_events`, FastAPI 미들웨어, 무결성 테스트 |
| **2주차** | 문서등록·버전관리 API | 문서·버전·파일 해시 API |
| **3주차** | DSS 서명 PoC | PAdES 서명·검증·감사기록 |
| **4주차** | RAG 파일럿 준비 | 승인 SOP 10건 색인, 평가 질문 세트 |

이 계획을 실행하면 **4주 내에 감사추적·문서버전·전자서명·RAG 검색의 최소 동작 구조**를 확보할 수 있으며, 이후 CAPA·교육·설계추적성·CSV 패키지를 순차적으로 확장하는 방식이 가장 투자 대비 효과가 높습니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/DSS/webapp-demo/signature-rest)