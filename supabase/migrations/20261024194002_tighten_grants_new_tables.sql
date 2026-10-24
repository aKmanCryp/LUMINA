/*
# Tighten grants on new tables: remove anon, restrict authenticated

## Problem
The previous migration created qr_codes, payment_notices, and audit_log
with service_role grants, but Postgres also gave anon full CRUD by default.
This removes anon access and restricts authenticated to minimum needed.

## Changes
- qr_codes: revoke anon; authenticated gets SELECT+INSERT+UPDATE+DELETE (admin-only via RLS)
- payment_notices: revoke anon; authenticated gets SELECT only (writes via functions)
- audit_log: revoke anon; authenticated gets SELECT only (admin-only via RLS)
- orders: revoke the stale INSERT policy (no more direct inserts; create_order RPC only)
*/

REVOKE SELECT, INSERT, UPDATE, DELETE ON qr_codes FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON payment_notices FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON audit_log FROM anon;

-- payment_notices: authenticated only needs SELECT (writes via submit_payment_notice RPC)
REVOKE INSERT, UPDATE, DELETE ON payment_notices FROM authenticated;
GRANT SELECT ON payment_notices TO authenticated;

-- audit_log: authenticated only needs SELECT (admin-only via RLS, inserts via functions)
REVOKE INSERT, UPDATE, DELETE ON audit_log FROM authenticated;
GRANT SELECT ON audit_log TO authenticated;

-- orders: drop the INSERT policy since clients no longer insert directly
DROP POLICY IF EXISTS "insert_own_orders" ON orders;