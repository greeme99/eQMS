import contextvars
from collections.abc import Callable
from typing import Any
from uuid import uuid4

from fastapi import Request, Response
from starlette.middleware.base import BaseHTTPMiddleware

# Context 변수 (스레드/태스크 로컬)
audit_context_var: contextvars.ContextVar[dict[str, Any]] = contextvars.ContextVar(
    "audit_context", default={}
)


def get_current_audit_context() -> dict[str, Any]:
    return audit_context_var.get()


class AuditContextMiddleware(BaseHTTPMiddleware):
    """
    모든 요청으로부터 클라이언트 IP, User-Agent, 변경 사유(X-Audit-Reason)를 추출하여
    감사추적 컨텍스트를 구성한다.
    """

    async def dispatch(self, request: Request, call_next: Callable[[Request], Any]) -> Response:
        trace_id = request.headers.get("X-Request-ID", str(uuid4()))
        client_ip = request.client.host if request.client else "unknown"
        user_agent = request.headers.get("User-Agent", "unknown")
        audit_reason = request.headers.get("X-Audit-Reason")

        context_data = {
            "trace_id": trace_id,
            "client_ip": client_ip,
            "user_agent": user_agent,
            "reason": audit_reason,
            "actor_id": None,  # 추후 인증 미들웨어/토큰 디코딩 후 채워짐
        }

        token = audit_context_var.set(context_data)
        request.state.audit_context = context_data

        try:
            response = await call_next(request)
            response.headers["X-Request-ID"] = trace_id
            return response
        finally:
            audit_context_var.reset(token)
