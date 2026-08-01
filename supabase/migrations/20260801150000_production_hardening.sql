-- Match the audit redaction routine volatility to the stable expressions used
-- by its recursive JSON traversal. This avoids unsafe immutable planner assumptions.
alter function app_security.redact_audit_json(jsonb) stable;
