from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class AuditEventBase(BaseModel):
    object_type: str = Field(..., max_length=50, description="대상 엔티티 종류 (e.g. document, capa)")
    object_id: UUID = Field(..., description="대상 엔티티 UUID")
    action: str = Field(..., max_length=30, description="수행 행위 (e.g. CREATE, UPDATE, APPROVE, SIGN)")
    before_state: dict[str, Any] | None = Field(default=None, description="변경 전 상태")
    after_state: dict[str, Any] | None = Field(default=None, description="변경 후 상태")
    reason: str | None = Field(default=None, description="변경 사유 (§11.10(e))")


class AuditEventCreate(AuditEventBase):
    actor_id: UUID | None = None
    actor_ip: str | None = None
    user_agent: str | None = None


class AuditEventResponse(AuditEventBase):
    model_config = ConfigDict(from_attributes=True)

    audit_id: int
    event_uuid: UUID
    actor_id: UUID | None = None
    actor_ip: str | None = None
    user_agent: str | None = None
    occurred_at: datetime
    prev_hash: str | None = None
    record_hash: str


class AuditTrailListResponse(BaseModel):
    total: int
    items: list[AuditEventResponse]
