# eQMS Backend Service

FastAPI 기반의 규제 준수형 eQMS 코어 백엔드 서비스입니다.

## 기능
- **감사추적 (Audit Trail)**: FDA 21 CFR §11.10(e) 요구사항을 만족하는 Append-Only 감사 이벤트 기록 및 해시체인 관리
- **감사 컨텍스트 미들웨어**: 모든 HTTP 요청에 대해 호출자 IP, User-Agent, X-Audit-Reason(변경 사유) 컨텍스트 자동 추출
- **상태 점검**: Liveness (`/healthz`) 및 Readiness (`/readyz`) 엔드포인트 제공

## 로컬 개발 환경 실행
```bash
python -m venv .venv
source .venv/bin/activate
pip install -e ".[dev]"

# 서버 실행
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## 단위 테스트 실행
```bash
pytest
```
