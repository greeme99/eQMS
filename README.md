# eQMS (Electronic Quality Management System)

> **의료기기·의료장비 제조사를 위한 규제 준수형 오픈소스 전자의료기기 품질경영시스템**

eQMS는 글로벌 의료기기 규제 요구사항(FDA 21 CFR Part 11, ISO 13485:2016, FDA QMSR, 국내 KGMP)을 준수하도록 설계된 오픈소스 기반 eQMS 플랫폼입니다. 자체 개발 규제 통제 계층(FastAPI + PostgreSQL)과 검증된 오픈소스 인프라(MinIO, Keycloak, EU DSS, Qdrant)를 결합하여 최소 투자로 완전한 규제 적합성과 컴퓨터 소프트웨어 보증(CSA/CSV) 체계를 확보합니다.

---

## 1. 주요 특징 및 준수 규제

- **기록 불변성 & 완전한 감사추적 (Audit Trail)**:
  - FDA 21 CFR §11.10(e) 준수
  - PostgreSQL DB 트리거 및 애플리케이션 이중 감사 기록
  - SHA-256 레코드 해시체인(Hash Chain) 기반 위·변조 탐지 및 Append-only 강제
- **신뢰할 수 있는 전자서명 (Electronic Signatures)**:
  - FDA 21 CFR Part 11 Subpart C 및 ISO 13485 Cl.4.2 준수
  - EU DSS(Digital Signature Service) 연동 PAdES(PDF Advanced Electronic Signatures) 3-step 비저장 전자서명 생성 및 실시간 검증
- **무결성 원본 보관소 (WORM Storage)**:
  - 승인된 공식 SOP 및 서명본 PDF의 덮어쓰기·임의 삭제 방지(MinIO Object Lock WORM 버킷)
- **엔터프라이즈 IAM & 접근 통제**:
  - Keycloak 기반 OIDC/SAML SSO, MFA(다중인증), 역할 기반 접근제어(RBAC)
- **규격·SOP 특화 RAG (검색 증강 생성)**:
  - 유효 승인 버전 문서만 색인 및 권한 필터링 검색
  - 답변 시 반드시 문서번호·버전·페이지 등 명시적 출처 제시 ("근거 부재 시 Unknown")
- **컴퓨터 소프트웨어 보증 (CSA / CSV) 패키지 병행 구축**:
  - GAMP 5 및 FDA CSA 가이드라인에 따른 URS, Risk Assessment, RTM, IQ/OQ/PQ 검증 패키지 내재화

---

## 2. 시스템 아키텍처

```text
[ 사용자 / 웹 브라우저 ]
        │ (HTTPS / OIDC)
        ▼
   [ Keycloak ] ── SSO · MFA · RBAC (§11.10(d), §11.300)
        │
        ▼
[ FastAPI eQMS Core API ] ── Audit Context Middleware (IP, User, Reason)
        │
        ├── [PostgreSQL 16] ────── 업무 데이터 + Append-Only Audit Trail (해시체인)
        ├── [MinIO WORM] ───────── 무결성 원본 PDF · PAdES 서명본 (Object Lock)
        ├── [EU DSS Engine] ────── PAdES 3-Step 전자서명 생성 및 검증
        └── [Qdrant + Ollama] ──── 규제 문서 RAG 파이프라인 (승인 문서 한정 검색)
```

---

## 3. 디렉토리 구조

```text
.
├── .Codex/               # 에이전트 하네스, 스킬 및 학습 루프 설정
├── Research/             # 규제(FDA/ISO/KGMP) 및 기술 아키텍처 조사 보고서 (P-eQMS-01~10)
├── backend/              # FastAPI 백엔드 애플리케이션
│   ├── app/
│   │   ├── api/          # REST API 라우터 (v1)
│   │   ├── core/         # 환경설정, DB 세션, 감사추적, 보안 미들웨어
│   │   ├── models/       # SQLAlchemy ORM 모델
│   │   ├── schemas/      # Pydantic 데이터 검증 스키마
│   │   └── main.py       # 애플리케이션 진입점
│   ├── tests/            # 단위 및 통합 테스트 (Pytest)
│   ├── Dockerfile        # 백엔드 컨테이너 빌드 파일
│   └── pyproject.toml    # 패키지 및 의존성 정의
├── docker/               # 인프라 설정 및 DB 초기화 스크립트
│   └── initdb/           # PostgreSQL 감사추적 스키마 초기화 SQL
├── docs/                 # CSV/CSA 검증 문서 (URS, VMP, Risk Assessment, RTM, IQ/OQ)
├── memory/               # 프로젝트 컨텍스트 및 사용자 규칙 메모리
├── docker-compose.yml    # 로컬 개발용 통합 컨테이너 환경
├── plan-eQMS.md          # eQMS 구축 마스터 플랜
├── plan-eQMS2.md         # 현행 규제 체계 반영 정밀 아키텍처 계획
└── README.md
```

---

## 4. 기술 스택

| 영역 | 기술 | 역할 및 근거 |
|---|---|---|
| **Core API** | Python 3.11+, FastAPI | 고성능 비동기 API, 타입 안전성, 감사추적 미들웨어 지원 |
| **Database** | PostgreSQL 16 | ACID 보장, 트리거 기반 감사추적 불변성 강제, pgcrypto |
| **Storage** | MinIO (S3 Compatible) | Object Lock WORM 기능으로 문서 원본 무결성 보존 |
| **IAM** | Keycloak | OIDC/SAML 인증, 21 CFR §11.300 준수 계정 관리 및 MFA |
| **전자서명** | EU DSS REST API | PAdES 표준 준수, 비저장 3-step 서명 및 LTV 검증 |
| **RAG / Vector** | Qdrant, Haystack, Ollama | 온프레미스 경량 벡터 검색 및 SOP 질의응답 |

---

## 5. 빠른 시작 (Quick Start)

### 5.1 사전 요구사항
- Docker & Docker Compose v2+
- Python 3.11+ (로컬 개발 시)

### 5.2 환경 변수 설정
```bash
cp .env.example .env
```

### 5.3 컨테이너 인프라 기동
로컬 필수 서비스(PostgreSQL, MinIO, Keycloak, Qdrant, DSS)를 Docker Compose로 기동합니다.

```bash
docker compose up -d db minio
# 전체 인프라 스택 실행 시:
docker compose up -d
```

| 서비스 | 접속 URL / 포트 | 기본 계정 (로컬 개발용) |
|---|---|---|
| **FastAPI Core** | http://localhost:8000 | `/docs` (Swagger UI) |
| **PostgreSQL** | `localhost:5432` | `eqms_user` / `eqms_password` (DB: `eqms`) |
| **MinIO Console** | http://localhost:9001 | `minioadmin` / `minioadmin123` |
| **Keycloak Admin** | http://localhost:8081 | `admin` / `admin` |
| **EU DSS Engine** | http://localhost:8080 | REST API |
| **Qdrant Vector** | http://localhost:6333 | REST API |

### 5.4 로컬 백엔드 실행
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# 개발 서버 구동
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### 5.5 헬스체크 및 감사추적 동작 확인
```bash
# 헬스체크
curl -i http://localhost:8000/healthz

# 감사추적 이벤트 목록 조회
curl -i http://localhost:8000/api/v1/audit-events
```

---

## 6. 개발 원칙 및 검증 가이드 (CSV/CSA)

- **선 검증, 후 주장 (Evidence Before Assertion)**: 규제 적합성은 코드만으로 완성되지 않으며, 제조사 절차, 권한 통제, CSV/CSA 적격성 평가 증적과 함께 검증합니다.
- **불변성 감사추적 강제**: `audit_events` 테이블의 레코드는 UPDATE 및 DELETE가 데이터베이스 레벨에서 원천 차단됩니다.
- **민감정보 마스킹**: 비밀번호, 토큰, 암호키 등은 감사 기록 시 자동 마스킹 처리됩니다.
- **테스트 실행**:
  ```bash
  cd backend
  pytest
  ```

---

## 7. 라이선스 및 준수 공지

본 프로젝트의 소스 코드는 내부 규제 검증 절차와 함께 배포되는 것을 전제로 합니다. 각 서드파티 오픈소스(Keycloak, MinIO, DSS, PostgreSQL 등)는 각 소프트웨어의 라이선스 조항을 따릅니다.
