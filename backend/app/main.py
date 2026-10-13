from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.middleware import AuditContextMiddleware


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 시작 시 처리 (DB 연결 확인 등)
    yield
    # 종료 시 리소스 정리


app = FastAPI(
    title=settings.PROJECT_NAME,
    version=settings.VERSION,
    description="Regulatory-Compliant eQMS API Backend (FDA 21 CFR Part 11 / ISO 13485:2016)",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url=f"{settings.API_V1_STR}/openapi.json",
)

# CORS 설정
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 21 CFR §11.10(e) 감사 컨텍스트 미들웨어 등록
app.add_middleware(AuditContextMiddleware)

# API v1 라우터 등록
app.include_router(api_router, prefix=settings.API_V1_STR)

# 루트 헬스체크 편의 제공
@app.get("/healthz", include_in_schema=False)
async def root_health():
    return {
        "status": "healthy",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
    }
