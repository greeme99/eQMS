아래는 **Phase 1 MVP → 21 CFR Part 11 → RAG·LLM → DHF/DMR(MDF) 모듈**로 이어지는 순차 개발 가이드입니다. 핵심 원칙은 “상용 eQMS 기능을 벤치마크하되, 규제 준수의 책임은 제조사가 가진다”는 점이며, Odoo·Nextcloud는 운영 기반으로 활용하되 Part 11 통제는 별도 검증된 커스텀 모듈로 구현하는 방식이 가장 현실적입니다. [adatasol](https://adatasol.com/industries/manufacturing/medical-device-manufacturing/)

***

## ① Executive Summary

1. **MVP는 문서통제 + 변경관리 + 감사추적**부터 시작합니다. Odoo 또는 Nextcloud를 문서·워크플로 기반으로 쓰고, 규제 기록용 감사추적·전자서명은 FastAPI/PostgreSQL 커스텀 모듈로 분리 구현합니다. [adatasol](https://adatasol.com/industries/manufacturing/medical-device-manufacturing/)
2. **FDA QMSR은 2026년 2월 2일부터 시행**되었으며, ISO 13485:2016을 참조합니다. 기존 DHF/DMR/DHR 용어는 각각 Design and Development File, Medical Device File(MDF), Production and Release Records 개념으로 재편되지만, 기록의 실질적 요구는 유지됩니다. [fda](https://www.fda.gov/medical-devices/postmarket-requirements-devices/quality-management-system-regulation-qmsr)
3. **감사추적은 append-only 설계**가 원칙입니다. 생성·수정·삭제를 시간·사용자·변경 전후값·사유와 함께 기록하고, 기존 기록을 UPDATE/DELETE로 덮어쓰지 않아야 합니다. 
4. **전자서명은 PDF PAdES 기반 DSS**를 권장합니다. EU DSS는 오픈소스 Java 라이브러리로 PAdES·XAdES·CAdES 서명 생성·검증을 지원하며, PDF 서명에는 PAdES가 적합합니다. [ecfr](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11)
5. **RAG는 Haystack + Qdrant + 온프레미스 LLM** 조합으로 구성합니다. 문서 색인 파이프라인과 질의 파이프라인을 분리하고, 출처 메타데이터와 문서 버전을 반드시 검색 결과에 노출해야 합니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/sites/spaces/DIGITAL/pages/467109107/Digital+Signature+Service+-+DSS)

***

## ② 1. eQMS 오픈소스 스택 비교

### 스택 비교 매트릭스

| 평가 항목 | Odoo | Nextcloud | FastAPI + PostgreSQL 커스텀 |
|---|---|---|---|
| **주 역할** | ERP·BOM·구매·재고·DHR 운영 기록 | 문서 저장·공유·협업·버전관리 | 규제 핵심 워크플로·감사추적·전자서명 |
| **문서관리** | 문서 모듈 및 첨부 가능 | 강점: Files, 버전관리, 공유, 감사 기능  [nextcloud](https://nextcloud.com/files/) | 메타데이터·승인·버전 정책 중심 |
| **품질 워크플로** | CAPA/NC/변경관리 커스텀 필요 | 승인 워크플로 중심, QMS 특화 아님 | URS 기반 맞춤 설계 |
| **감사추적** | 설정·커스텀 필요, 기본 제공으로 Part 11 보장 불가  [adatasol](https://adatasol.com/industries/manufacturing/medical-device-manufacturing/) | 감사 기능 제공하나 규제 기록 수준 별도 검증 필요  [nextcloud](https://nextcloud.com/files/) | append-only Audit Trail 직접 구현 |
| **전자서명** | 커스텀 필요  [adatasol](https://adatasol.com/industries/manufacturing/medical-device-manufacturing/) | 외부 연동 필요 | DSS PAdES 연동 권장  [ecfr](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11) |
| **RAG·LLM** | 별도 구축 | 별도 구축 | Haystack+Qdrant 직접 통합  [ec.europa](https://ec.europa.eu/digital-building-blocks/sites/spaces/DIGITAL/pages/467109107/Digital+Signature+Service+-+DSS) |
| **추천 용도** | 생산·품질·물류 운영 기록 | SOP·절차서·기술문서 저장소 | Part 11 통제 계층 |

### 권장 아키텍처

```text
[사용자]
   │ HTTPS
   ▼
[Nextcloud]  ── SOP·절차서·DMR 첨부파일·버전관리
   │ Webhook / API
   ▼
[FastAPI eQMS Core] ── 문서승인·변경관리·CAPA·교육·전자서명
   │
   ├── [PostgreSQL Primary/Standby] ── 업무 데이터 + Audit Trail
   ├── [MinIO/S3 WORM] ── 원본 문서 무결성 저장
   ├── [Keycloak] ── SSO·MFA·RBAC
   ├── [DSS 서비스] ── PDF PAdES 서명·검증
   └── [Haystack + Qdrant + Ollama] ── SOP/규격 RAG
```

**중요**: Odoo는 ERP·DHR·추적성 기록 계층에 유용하지만, “Odoo 자체가 검증된 Part 11 시스템”이라고 보면 안 됩니다. 전자서명·감사추적·변경관리는 제조사가 구현·검증·문서화해야 합니다. [adatasol](https://adatasol.com/industries/manufacturing/medical-device-manufacturing/)

***

## ③ 2. GMP 단계별 구축 가이드

### 단계별 로드맵

| 단계 | 기간 | 목표 | 핵심 산출물 |
|---|---:|---|---|
| **0. 준비** | 2~4주 | 범위·역할·위험도 정의 | 시스템 인벤토리, GAMP 분류, URS 초안 |
| **1. MVP** | 4~8주 | SOP 문서통제·변경관리·감사추적 | 문서등록, 승인, 버전, Audit Trail |
| **2. Part 11** | 6~10주 | 전자서명·접근통제·기록무결성 | PAdES 서명, RBAC, 백업·복구, CSV IQ/OQ |
| **3. 품질운영** | 8~12주 | NC/CAPA/교육/내부감사 | CAPA 워크플로, 교육이수, 시정조치 |
| **4. RAG·LLM** | 6~8주 | SOP·규격 검색 AI 비서 | 색인, 검색, 출처인용, 접근권한 필터 |
| **5. MDF/DHF** | 8~12주 | 설계·제품 기록 관리 | Design File, MDF, Traceability Matrix |
| **6. 운영전환** | 2~4주 | CSV PQ 및 이관 | Validation Report, Change Control, 교육 |

### 최소 투자 원칙

- **Phase 1은 엑셀 대체**에 집중합니다. 문서 등록·개정·승인·배포·회수만 먼저 전산화합니다.
- **CAPA·교육은 Phase 3**로 미루되, 문서 개정 시 교육 대상자 알림은 Phase 1에 최소 기능으로 포함합니다.
- **RAG는 Phase 4**에 도입하되, 검색 대상은 승인 완료 문서로 한정합니다.
- **CSV는 기능 개발 후가 아니라 개발과 병행**해 URS·위험평가·테스트케이스를 축적합니다.

***

## ④ 3. Phase 1 MVP 아키텍처·기능 설계

### MVP 범위

| 모듈 | 핵심 기능 | 제외 기능 |
|---|---|---|
| **문서통제** | SOP 등록, 개정, 승인, 배포, 회수 | 자동 교육이수 |
| **변경관리** | 변경요청, 영향평가, 승인, 실행 | 설계변경 자동 연계 |
| **감사추적** | 생성·수정·승인·조회 기록 | 외부 시스템 전체 감사 |
| **사용자·권한** | 로그인, 역할, 승인권한 | 부서별 세분화 권한 |
| **보고** | 문서현황, 지연승인, 변경이력 | 경영 BI |

### 데이터 모델

```text
users(id, employee_no, name, email, role, is_active)
documents(id, doc_no, title, doc_type, current_version, status, owner_id)
document_versions(id, document_id, version, file_id, status, effective_date)
document_approvals(id, version_id, approver_id, role, decision, signed_at, signature_id)
change_requests(id, cr_no, title, reason, impact, status, requester_id)
audit_events(id, event_id, object_type, object_id, action, before, after, actor_id, reason, occurred_at)
files(id, sha256, storage_path, mime_type, size, created_at)
```

### MVP 핵심 API

| API | Method | 기능 |
|---|---|---|
| `/api/documents` | POST | 문서 등록 |
| `/api/documents/{id}/versions` | POST | 신규 버전 등록 |
| `/api/documents/{id}/submit` | POST | 승인 요청 |
| `/api/approvals/{id}/sign` | POST | 전자서명·승인 |
| `/api/change-requests` | POST | 변경요청 생성 |
| `/api/audit-events` | GET | 감사기록 조회 |
| `/api/rag/ask` | POST | SOP 질의응답 |

***

## ⑤ 4. 21 CFR Part 11 감사추적 SQL·전자서명 코드

### 4.1 감사추적 SQL

21 CFR Part 11은 전자기록의 생성·수정·삭제에 대해 안전하고 컴퓨터가 생성한 시간 기록 감사추적을 요구하며, 이전 기록이 가려지지 않아야 합니다. 

```sql
-- 1. 사용자
CREATE TABLE users (
    user_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    employee_no    VARCHAR(30) UNIQUE NOT NULL,
    full_name      VARCHAR(100) NOT NULL,
    email          VARCHAR(255) UNIQUE NOT NULL,
    role           VARCHAR(30) NOT NULL,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. 감사추적: UPDATE/DELETE 금지
CREATE TABLE audit_events (
    audit_id       BIGSERIAL PRIMARY KEY,
    event_uuid     UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type    VARCHAR(50) NOT NULL,
    object_id      UUID NOT NULL,
    action         VARCHAR(20) NOT NULL
                   CHECK (action IN ('CREATE','READ','UPDATE','DELETE','SIGN','APPROVE','REJECT','EXPORT')),
    before_state   JSONB,
    after_state    JSONB,
    actor_id       UUID NOT NULL REFERENCES users(user_id),
    actor_ip       INET,
    reason         TEXT,
    occurred_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    record_hash    CHAR(64) NOT NULL
);

CREATE INDEX idx_audit_object ON audit_events(object_type, object_id, occurred_at);
CREATE INDEX idx_audit_actor ON audit_events(actor_id, occurred_at);

-- 3. 규제 기록 무결성: 직접 수정·삭제 차단
CREATE RULE audit_events_no_update AS
ON UPDATE TO audit_events DO INSTEAD NOTHING;

CREATE RULE audit_events_no_delete AS
ON DELETE TO audit_events DO INSTEAD NOTHING;
```

### 4.2 감사추적 기록 함수

```sql
CREATE OR REPLACE FUNCTION fn_write_audit(
    p_object_type VARCHAR,
    p_object_id UUID,
    p_action VARCHAR,
    p_before JSONB,
    p_after JSONB,
    p_actor_id UUID,
    p_actor_ip INET,
    p_reason TEXT
) RETURNS UUID AS $$
DECLARE
    v_event_uuid UUID := gen_random_uuid();
    v_hash CHAR(64);
BEGIN
    SELECT encode(digest(
        concat_ws('|',
            v_event_uuid,
            p_object_type,
            p_object_id,
            p_action,
            coalesce(p_before::text, ''),
            coalesce(p_after::text, ''),
            p_actor_id,
            now()
        ), 'sha256'), 'hex')
    INTO v_hash;

    INSERT INTO audit_events (
        event_uuid, object_type, object_id, action,
        before_state, after_state, actor_id, actor_ip, reason, record_hash
    ) VALUES (
        v_event_uuid, p_object_type, p_object_id, p_action,
        p_before, p_after, p_actor_id, p_actor_ip, p_reason, v_hash
    );

    RETURN v_event_uuid;
END;
$$ LANGUAGE plpgsql;
```

### 4.3 FastAPI 감사추적 미들웨어

```python
# app/audit.py
import hashlib
import json
from datetime import datetime, timezone
from sqlalchemy import text
from fastapi import Request

SENSITIVE_FIELDS = {"password", "token", "secret"}

def sanitize(data: dict | None):
    if not data:
        return None
    return {
        k: ("***" if k.lower() in SENSITIVE_FIELDS else v)
        for k, v in data.items()
    }

async def write_audit(
    db,
    object_type: str,
    object_id: str,
    action: str,
    before: dict | None,
    after: dict | None,
    actor_id: str,
    request: Request,
    reason: str | None = None,
):
    payload = {
        "object_type": object_type,
        "object_id": object_id,
        "action": action,
        "before": sanitize(before),
        "after": sanitize(after),
        "actor_id": actor_id,
        "actor_ip": request.client.host,
        "reason": reason,
        "occurred_at": datetime.now(timezone.utc).isoformat(),
    }

    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False)
    payload["record_hash"] = hashlib.sha256(raw.encode()).hexdigest()

    await db.execute(text("""
        INSERT INTO audit_events
        (event_uuid, object_type, object_id, action, before_state,
         after_state, actor_id, actor_ip, reason, occurred_at, record_hash)
        VALUES
        (gen_random_uuid(), :object_type, :object_id, :action,
         CAST(:before AS JSONB), CAST(:after AS JSONB),
         :actor_id, :actor_ip, :reason, :occurred_at, :record_hash)
    """), payload)
    await db.commit()
```

### 4.4 DSS 전자서명 연동

EU DSS는 Java 기반 오픈소스 서명 라이브러리로, PAdES PDF 서명 생성·검증을 지원합니다. Python 백엔드에서는 DSS를 별도 REST 서비스로 띄우고 호출하는 방식이 유지보수에 유리합니다. [ecfr](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11)

```python
# app/signature.py
import httpx
from fastapi import HTTPException

DSS_BASE_URL = "http://dss-service:8080"

async def sign_pdf(
    pdf_bytes: bytes,
    signer_certificate_b64: str,
    signer_pin: str,
    signature_meaning: str,
):
    """
    1. PDF 원문을 DSS 서비스로 전송
    2. PAdES 서명 생성
    3. 서명자·서명의미·시각을 문서 및 감사추적에 연결
    """
    files = {"file": ("document.pdf", pdf_bytes, "application/pdf")}
    data = {
        "signatureForm": "PAdES",
        "packaging": "ENVELOPING",
        "digestAlgorithm": "SHA256",
        "signerCertificate": signer_certificate_b64,
        "signerPin": signer_pin,
        "signatureMeaning": signature_meaning,
    }

    async with httpx.AsyncClient(timeout=60) as client:
        response = await client.post(
            f"{DSS_BASE_URL}/api/sign/pdf",
            files=files,
            data=data,
        )

    if response.status_code != 200:
        raise HTTPException(status_code=502, detail="PDF signing failed")

    return response.content
```

### 4.5 전자서명 API

```python
# app/routers/approval.py
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

router = APIRouter(prefix="/api/approvals")

class ApprovalSignRequest(BaseModel):
    approval_id: str
    document_version_id: str
    decision: str  # APPROVE | REJECT
    reason: str
    signer_certificate_b64: str
    signer_pin: str

@router.post("/sign")
async def sign_approval(
    body: ApprovalSignRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    if body.decision not in {"APPROVE", "REJECT"}:
        raise HTTPException(400, "Invalid decision")

    before = await get_approval_state(db, body.approval_id)

    pdf_bytes = await get_document_pdf(db, body.document_version_id)

    signed_pdf = await sign_pdf(
        pdf_bytes=pdf_bytes,
        signer_certificate_b64=body.signer_certificate_b64,
        signer_pin=body.signer_pin,
        signature_meaning=body.decision,
    )

    await save_signed_pdf(db, body.document_version_id, signed_pdf)
    await update_approval_state(
        db,
        approval_id=body.approval_id,
        decision=body.decision,
        signed_by=current_user.user_id,
    )

    await write_audit(
        db=db,
        object_type="document_approval",
        object_id=body.approval_id,
        action="SIGN",
        before=before,
        after={"decision": body.decision, "signed": True},
        actor_id=current_user.user_id,
        request=request,
        reason=body.reason,
    )

    return {"status": "signed", "approval_id": body.approval_id}
```

**검증 포인트**: 서명자 이름, 서명 시각, 서명 의미(승인/검토/책임)가 전자기록과 연결되어야 하며, 서명 후 원문 변경을 탐지할 수 있어야 합니다. [fda](https://www.fda.gov/media/166215/download)

***

## ⑥ 5. ISO 13485·FDA QMSR용 DHF/DMR 관리 모듈

### 5.1 용어 전환

FDA QMSR은 2026년 2월 2일부터 시행되었고 ISO 13485:2016을 참조합니다. 기존 DHF·DMR·DHR 명칭은 규제 용어에서 사라졌지만, 기록 요구 자체는 유지됩니다. [fda](https://www.fda.gov/medical-devices/postmarket-requirements-devices/quality-management-system-regulation-qmsr)

| 기존 용어 | QMSR/ISO 13485 관점 | 시스템 모듈 |
|---|---|---|
| **DHF** | Design and Development File, ISO 13485 Clause 7.3.10  [fda](https://www.fda.gov/media/189041/download) | 설계개발 파일 |
| **DMR** | Medical Device File(MDF), ISO 13485 Clause 4.2.3  [aami](https://aami.org/news/navigating-fda-qmsr-transition-regulation/) | 제품기준·제조기준 파일 |
| **DHR** | Production and Release Records  [aami](https://aami.org/news/navigating-fda-qmsr-transition-regulation/) | 생산·출하 기록 |

### 5.2 Design and Development File 모듈

설계개발 파일에는 설계계획, 설계입력, 설계출력, 설계검토, 검증·확인, 설계이전, 설계변경 기록이 포함되어야 합니다. [qdrant](https://qdrant.tech/documentation/examples/rag-chatbot-red-hat-openshift-haystack/)

```text
DesignProject
 ├── DesignPlan
 ├── UserNeeds
 ├── DesignInputs
 ├── DesignOutputs
 ├── RiskFile (ISO 14971)
 ├── DesignReviews
 ├── V&VRecords
 ├── DesignTransfer
 └── DesignChanges
```

```sql
CREATE TABLE design_projects (
    project_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_code VARCHAR(30) UNIQUE NOT NULL,
    device_family VARCHAR(100) NOT NULL,
    intended_use TEXT NOT NULL,
    status VARCHAR(30) NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE design_records (
    record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID NOT NULL REFERENCES design_projects(project_id),
    record_type VARCHAR(40) NOT NULL
        CHECK (record_type IN (
            'PLAN','USER_NEED','INPUT','OUTPUT','RISK',
            'REVIEW','VERIFICATION','VALIDATION','TRANSFER','CHANGE'
        )),
    title VARCHAR(200) NOT NULL,
    document_version_id UUID REFERENCES document_versions(id),
    parent_record_id UUID REFERENCES design_records(record_id),
    status VARCHAR(30) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE design_traceability (
    trace_id BIGSERIAL PRIMARY KEY,
    source_record_id UUID NOT NULL REFERENCES design_records(record_id),
    target_record_id UUID NOT NULL REFERENCES design_records(record_id),
    relation_type VARCHAR(30) NOT NULL
        CHECK (relation_type IN ('TRACES_TO','VERIFIES','VALIDATES','DERIVES_FROM'))
);
```

### 5.3 Medical Device File(MDF) 모듈

기존 DMR의 실질 내용인 제품 사양, 생산·공정 사양, 품질보증 절차, 포장·라벨링, 설치·유지·서비스 절차는 MDF로 관리합니다. [aami](https://aami.org/news/navigating-fda-qmsr-transition-regulation/)

```sql
CREATE TABLE medical_device_files (
    mdf_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mdf_code VARCHAR(30) UNIQUE NOT NULL,
    device_family VARCHAR(100) NOT NULL,
    current_version VARCHAR(20) NOT NULL,
    status VARCHAR(30) NOT NULL,
    owner_id UUID NOT NULL REFERENCES users(user_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE mdf_sections (
    section_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    mdf_id UUID NOT NULL REFERENCES medical_device_files(mdf_id),
    section_type VARCHAR(40) NOT NULL
        CHECK (section_type IN (
            'DEVICE_SPEC','PROCESS_SPEC','QA_PROCEDURE',
            'PACKAGING_LABELING','INSTALLATION_MAINTENANCE_SERVICE'
        )),
    title VARCHAR(200) NOT NULL,
    document_version_id UUID REFERENCES document_versions(id),
    status VARCHAR(30) NOT NULL,
    effective_date DATE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

### 5.4 추적성 화면 설계

| 화면 | 핵심 기능 |
|---|---|
| **Design Traceability Matrix** | User Need → Input → Output → Risk → V&V → Change 연결 |
| **MDF Index** | 제품별 사양·절차·라벨링·서비스 문서 일괄 조회 |
| **Change Impact** | 문서 개정 시 영향받는 설계·MDF·CAPA 자동 표시 |
| **Audit Viewer** | 기록별 생성·수정·승인·서명 이력 조회 |

***

## ⑦ RAG 파이프라인 구성

### 7.1 아키텍처

```text
[Nextcloud 승인 문서]
        │
        ▼
[문서 수집기] ── PDF/DOCX 파싱
        │
        ▼
[청킹 + 메타데이터 부착]
 doc_no, version, status, effective_date, owner, access_role
        │
        ▼
[FastEmbed 임베딩]
        │
        ▼
[Qdrant Vector Store]
        │
        ▼
[Haystack 검색 파이프라인]
        │
        ▼
[Ollama / Llama 3.1 Aloe]
        │
        ▼
[출처 인용 + 접근권한 필터 + 감사추적]
```

Haystack은 문서 파싱·청킹·임베딩·검색·생성 파이프라인을 제공하며, Qdrant와 결합해 사내 문서 기반 RAG를 구성할 수 있습니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/sites/spaces/DIGITAL/pages/467109107/Digital+Signature+Service+-+DSS)

### 7.2 설치

```bash
pip install haystack-ai qdrant-haystack fastembed-haystack pypdf
```

Qdrant는 문서 메타데이터를 payload로 저장하고, 검색 시 메타데이터 필터링을 지원합니다. 이를 활용해 **승인 완료 문서만 검색**되도록 제한합니다. [learn.microsoft](https://learn.microsoft.com/en-us/azure/storage/files/artificial-intelligence/retrieval-augmented-generation/open-source-frameworks/tutorials/haystack-qdrant/tutorial-haystack-qdrant)

### 7.3 문서 색인 코드

```python
# rag/index_documents.py
from haystack import Pipeline
from haystack.components.converters import PyPDFToDocument
from haystack.components.preprocessors import DocumentCleaner, DocumentSplitter
from haystack.components.embedders import SentenceTransformersDocumentEmbedder
from haystack.components.writers import DocumentWriter
from haystack_integrations.document_stores.qdrant import QdrantDocumentStore

document_store = QdrantDocumentStore(
    url="http://qdrant:6333",
    index="gmp_sop",
    embedding_dim=384,
    recreate_index=False,
    return_embedding=True,
)

indexing_pipeline = Pipeline()

indexing_pipeline.add_component("converter", PyPDFToDocument())
indexing_pipeline.add_component("cleaner", DocumentCleaner())
indexing_pipeline.add_component(
    "splitter",
    DocumentSplitter(split_by="word", split_length=300, split_overlap=50)
)
indexing_pipeline.add_component(
    "embedder",
    SentenceTransformersDocumentEmbedder(
        model="BAAI/bge-small-en-v1.5",
        meta_fields_to_embed=[
            "doc_no", "title", "version",
            "status", "effective_date", "access_role"
        ]
    )
)
indexing_pipeline.add_component(
    "writer",
    DocumentWriter(document_store=document_store)
)

indexing_pipeline.connect("converter", "cleaner")
indexing_pipeline.connect("cleaner", "splitter")
indexing_pipeline.connect("splitter", "embedder")
indexing_pipeline.connect("embedder", "writer")
```

### 7.4 질의 파이프라인

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
1. 제공된 문서 근거만 사용합니다.
2. 근거가 없으면 "확인된 내부 문서 근거가 없습니다"라고 답합니다.
3. 반드시 문서번호, 버전, 유효일을 함께 인용합니다.
4. 최종 판단·승인은 품질담당자가 수행해야 함을 안내합니다.

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
    SentenceTransformersTextEmbedder(model="BAAI/bge-small-en-v1.5")
)
query_pipeline.add_component(
    "retriever",
    QdrantEmbeddingRetriever(document_store=document_store, top_k=5)
)
query_pipeline.add_component("prompt_builder", PromptBuilder(template=template))
query_pipeline.add_component(
    "generator",
    OllamaChatGenerator(model="llama3.1:8b", url="http://ollama:11434")
)

query_pipeline.connect("text_embedder.embedding", "retriever.query_embedding")
query_pipeline.connect("retriever.documents", "prompt_builder.documents")
query_pipeline.connect("prompt_builder", "generator")
```

### 7.5 RAG API

```python
# app/routers/rag.py
from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel

router = APIRouter(prefix="/api/rag")

class RagRequest(BaseModel):
    question: str

@router.post("/ask")
async def ask_sop(
    body: RagRequest,
    request: Request,
    current_user=Depends(get_current_user),
    db=Depends(get_db),
):
    result = query_pipeline.run({
        "text_embedder": {"text": body.question},
        "prompt_builder": {"question": body.question},
        "retriever": {
            "filters": {
                "operator": "AND",
                "conditions": [
                    {"field": "meta.status", "operator": "==", "value": "APPROVED"},
                    {"field": "meta.access_role", "operator": "in", "value": current_user.roles},
                ],
            }
        },
    })

    answer = result["generator"]["replies"][0].content
    sources = [
        {
            "doc_no": d.meta.get("doc_no"),
            "title": d.meta.get("title"),
            "version": d.meta.get("version"),
            "effective_date": d.meta.get("effective_date"),
        }
        for d in result["retriever"]["documents"]
    ]

    await write_audit(
        db=db,
        object_type="rag_query",
        object_id=current_user.user_id,
        action="READ",
        before=None,
        after={"question": body.question, "sources": sources},
        actor_id=current_user.user_id,
        request=request,
        reason="SOP RAG query",
    )

    return {"answer": answer, "sources": sources}
```

***

## ⑧ CSV 및 운영전환 체크리스트

| 단계 | 필수 산출물 | 통과 기준 |
|---|---|---|
| **URS** | 요구사항 목록, 수용기준 | 모든 요구사항에 ID·검증방법 부여 |
| **위험평가** | 기능별 위험·통제 매핑 | 고위험 기능에 IQ/OQ 케이스 존재 |
| **IQ** | 설치·환경·백업·권한 확인 | DB 이중화, WORM, 계정·MFA 확인 |
| **OQ** | 감사추적·서명·권한 테스트 | 무단 UPDATE/DELETE 차단, 서명자 식별 확인 |
| **PQ** | 실무 시나리오 테스트 | SOP 개정→승인→배포→RAG 검색 전 과정 통과 |
| **Validation Report** | 검증요약·잔여리스크·운영승인 | 품질책임자 승인 |
| **Change Control** | 이관계획·테스트·승인 | 개발→운영 환경 분리 및 승인 이력 확보 |

CSV는 시스템이 의도된 용도에 따라 일관되게 작동함을 문서화된 증거로 입증하는 절차이며, URS부터 IQ/OQ/PQ, 변경통제까지 연결하는 것이 핵심입니다. 

***

## ⑨ 불확실성 및 주의사항

- **Odoo·Nextcloud는 그 자체로 “Part 11 인증 제품”이 아닙니다.** 제조사의 절차, 권한통제, 검증, 운영관리가 결합되어야 규제 준수가 성립합니다. [adatasol](https://adatasol.com/industries/manufacturing/medical-device-manufacturing/)
- **DSS는 eIDAS·PAdES 중심**입니다. 미국 규제 환경에서도 기술적으로 유용하지만, 회사의 전자서명 정책·인증서 운영·서명의미 정의를 별도로 문서화해야 합니다. [ecfr](https://www.ecfr.gov/current/title-21/chapter-I/subchapter-A/part-11)
- **RAG 답변은 품질 판단으로 사용하지 않습니다.** 반드시 출처 문서·버전·유효일을 제시하고, 최종 해석·승인은 담당자가 수행하도록 UI와 SOP에 명시합니다. [ec.europa](https://ec.europa.eu/digital-building-blocks/sites/spaces/DIGITAL/pages/467109107/Digital+Signature+Service+-+DSS)
- **기존 DHF/DMR/DHR 명칭은 사라졌지만 기록 요구는 유지**되므로, 기존 문서 색인과 신규 MDF·Design File 색인을 병행 운영하는 이중 매핑표를 권장합니다. [aami](https://aami.org/news/navigating-fda-qmsr-transition-regulation/)

***

## ⑩ 다음 단계 제안

1. **Phase 1 백로그 작성**: 문서등록 → 버전생성 → 승인요청 → 감사추적 → 배포 순으로 2주 단위 스프린트 구성
2. **감사추적 PoC 우선 구현**: PostgreSQL `audit_events` + FastAPI 미들웨어로 1주 내 동작 확인
3. **DSS 서명 PoC**: 샘플 SOP PDF 1건에 PAdES 서명·검증 테스트
4. **RAG 파일럿**: 승인된 SOP 10~20건으로 색인 후, 품질담당자 3~5명 대상 질의 정확도 평가
5. **CSV 패키지 병행 작성**: URS, Risk Assessment, IQ/OQ 테스트케이스를 기능 개발과 동시에 축적