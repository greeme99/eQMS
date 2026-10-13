import hashlib
import json
from datetime import datetime
from typing import Any
from uuid import UUID

SENSITIVE_KEYS = {
    "password",
    "token",
    "secret",
    "pin",
    "private_key",
    "keystore_password",
    "access_token",
    "refresh_token",
}


def mask_sensitive_data(data: Any) -> Any:
    """민감정보 키를 검출하여 '***'으로 마스킹 처리한다."""
    if isinstance(data, dict):
        sanitized = {}
        for key, value in data.items():
            if str(key).lower() in SENSITIVE_KEYS:
                sanitized[key] = "***"
            elif isinstance(value, (dict, list)):
                sanitized[key] = mask_sensitive_data(value)
            else:
                sanitized[key] = value
        return sanitized
    elif isinstance(data, list):
        return [mask_sensitive_data(item) for item in data]
    return data


def compute_audit_hash(
    prev_hash: str | None,
    object_type: str,
    object_id: UUID | str,
    action: str,
    occurred_at: datetime,
    actor_id: UUID | str | None = None,
    before_state: dict[str, Any] | None = None,
    after_state: dict[str, Any] | None = None,
    reason: str | None = None,
) -> str:
    """감사 기록의 SHA-256 해시를 계산하여 레코드 해시체인을 형성한다."""
    prev = prev_hash if prev_hash else "GENESIS"
    actor_str = str(actor_id) if actor_id else ""
    reason_str = reason or ""

    before_str = (
        json.dumps(mask_sensitive_data(before_state), sort_keys=True, ensure_ascii=False)
        if before_state
        else ""
    )
    after_str = (
        json.dumps(mask_sensitive_data(after_state), sort_keys=True, ensure_ascii=False)
        if after_state
        else ""
    )

    # 타임스탬프 표준 포맷 (ISO 8601 UTC)
    ts_str = occurred_at.strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    payload = (
        f"{prev}|{object_type}|{str(object_id)}|{action}|"
        f"{ts_str}|{actor_str}|{before_str}|{after_str}|{reason_str}"
    )

    return hashlib.sha256(payload.encode("utf-8")).hexdigest()
