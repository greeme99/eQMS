from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models.audit import AuditEvent
from app.schemas.audit import AuditEventResponse, AuditTrailListResponse

router = APIRouter()


@router.get("/audit-events", response_model=AuditTrailListResponse)
async def list_audit_events(
    object_type: str | None = Query(default=None, description="엔티티 종류 필터"),
    object_id: UUID | None = Query(default=None, description="엔티티 ID 필터"),
    action: str | None = Query(default=None, description="행위 필터"),
    limit: int = Query(default=50, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: AsyncSession = Depends(get_db),
):
    """
    감사추적 이벤트 목록을 시간 역순으로 조회한다. (21 CFR §11.10(e))
    """
    stmt = select(AuditEvent)
    count_stmt = select(func.count(AuditEvent.audit_id))

    if object_type:
        stmt = stmt.where(AuditEvent.object_type == object_type)
        count_stmt = count_stmt.where(AuditEvent.object_type == object_type)
    if object_id:
        stmt = stmt.where(AuditEvent.object_id == object_id)
        count_stmt = count_stmt.where(AuditEvent.object_id == object_id)
    if action:
        stmt = stmt.where(AuditEvent.action == action)
        count_stmt = count_stmt.where(AuditEvent.action == action)

    total_res = await db.execute(count_stmt)
    total = total_res.scalar_one()

    stmt = stmt.order_by(AuditEvent.occurred_at.desc(), AuditEvent.audit_id.desc())
    stmt = stmt.limit(limit).offset(offset)

    result = await db.execute(stmt)
    items = result.scalars().all()

    return AuditTrailListResponse(total=total, items=list(items))
