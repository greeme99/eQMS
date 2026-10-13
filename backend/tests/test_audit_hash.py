from datetime import datetime, timezone
from uuid import uuid4

from app.core.audit import compute_audit_hash, mask_sensitive_data


def test_mask_sensitive_data():
    payload = {
        "username": "tester",
        "password": "supersecretpassword",
        "nested": {
            "token": "bearer-xyz",
            "normal_field": "visible",
            "private_key": "-----BEGIN PRIVATE KEY-----",
        },
    }
    sanitized = mask_sensitive_data(payload)

    assert sanitized["username"] == "tester"
    assert sanitized["password"] == "***"
    assert sanitized["nested"]["token"] == "***"
    assert sanitized["nested"]["private_key"] == "***"
    assert sanitized["nested"]["normal_field"] == "visible"


def test_compute_audit_hash_deterministic():
    obj_id = uuid4()
    now = datetime(2026, 10, 13, 12, 0, 0, tzinfo=timezone.utc)

    hash1 = compute_audit_hash(
        prev_hash="GENESIS",
        object_type="document",
        object_id=obj_id,
        action="CREATE",
        occurred_at=now,
        actor_id=None,
        before_state=None,
        after_state={"title": "SOP-001", "version": "1.0"},
        reason="초기 등록",
    )

    hash2 = compute_audit_hash(
        prev_hash="GENESIS",
        object_type="document",
        object_id=obj_id,
        action="CREATE",
        occurred_at=now,
        actor_id=None,
        before_state=None,
        after_state={"title": "SOP-001", "version": "1.0"},
        reason="초기 등록",
    )

    assert len(hash1) == 64
    assert hash1 == hash2

    # 상태 변경 시 해시가 달라지는지 확인
    hash3 = compute_audit_hash(
        prev_hash="GENESIS",
        object_type="document",
        object_id=obj_id,
        action="CREATE",
        occurred_at=now,
        actor_id=None,
        before_state=None,
        after_state={"title": "SOP-001", "version": "1.1"},
        reason="초기 등록",
    )
    assert hash1 != hash3
