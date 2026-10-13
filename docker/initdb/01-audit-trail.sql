-- ====================================================================
-- eQMS PostgreSQL Schema: Audit Trail (21 CFR Part 11 Compliance)
-- ====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. 감사추적 기본 테이블 (Append-Only)
CREATE TABLE IF NOT EXISTS audit_events (
    audit_id      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    event_uuid    UUID NOT NULL DEFAULT gen_random_uuid(),
    object_type   VARCHAR(50) NOT NULL,
    object_id     UUID NOT NULL,
    action        VARCHAR(30) NOT NULL,
    before_state  JSONB,
    after_state   JSONB,
    actor_id      UUID,
    actor_ip      INET,
    user_agent    TEXT,
    reason        TEXT,
    occurred_at   TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    prev_hash     CHAR(64),
    record_hash   CHAR(64) NOT NULL
);

-- 인덱스 생성
CREATE INDEX IF NOT EXISTS idx_audit_object ON audit_events(object_type, object_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_actor  ON audit_events(actor_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_events(action, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_time   ON audit_events(occurred_at DESC);

-- 2. 불변성 보장 (UPDATE 및 DELETE 원천 차단 트리거)
CREATE OR REPLACE FUNCTION reject_audit_mutation()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'audit_events is append-only: % is not permitted (§11.10(e))', TG_OP
        USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_no_mutation ON audit_events;
CREATE TRIGGER trg_audit_no_mutation
BEFORE UPDATE OR DELETE ON audit_events
FOR EACH ROW EXECUTE FUNCTION reject_audit_mutation();

-- 3. 해시 계산 함수 (SHA-256)
CREATE OR REPLACE FUNCTION compute_audit_hash(
    p_prev_hash TEXT,
    p_object_type TEXT,
    p_object_id UUID,
    p_action TEXT,
    p_occurred_at TIMESTAMPTZ,
    p_actor_id UUID,
    p_before_state JSONB,
    p_after_state JSONB,
    p_reason TEXT
)
RETURNS CHAR(64) LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
    raw_text TEXT;
BEGIN
    raw_text := COALESCE(p_prev_hash, 'GENESIS') || '|' ||
                p_object_type || '|' ||
                p_object_id::TEXT || '|' ||
                p_action || '|' ||
                to_char(p_occurred_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"') || '|' ||
                COALESCE(p_actor_id::TEXT, '') || '|' ||
                COALESCE(p_before_state::TEXT, '') || '|' ||
                COALESCE(p_after_state::TEXT, '') || '|' ||
                COALESCE(p_reason, '');
    RETURN encode(digest(convert_to(raw_text, 'UTF8'), 'sha256'), 'hex');
END;
$$;
