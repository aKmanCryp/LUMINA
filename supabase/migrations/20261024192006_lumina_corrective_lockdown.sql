/*
# Corrective migration: lock down order columns, add profile trigger, remove anon grants

## Problems Fixed

1. orders: clients could UPDATE any column (amount, payment_status, result, user_id, etc.)
   — Revoked broad grant; clients get no UPDATE on orders at all.
2. orders: clients could INSERT arbitrary amounts/statuses — INSERT restricted to
   (product, payload) columns only; all other columns use secure defaults.
3. profiles: no auto-creation on signup — Added trigger on auth.users to create
   profile with is_admin=false automatically. Client upsert removed.
4. profiles/orders: anon had full CRUD — Revoked all anon grants.
5. is_admin column — Only display_name is client-updatable. is_admin is never
   writable by clients.

## Security Changes
- orders: GRANT SELECT to authenticated; GRANT INSERT (product, payload) to authenticated;
  no UPDATE/DELETE to authenticated. service_role gets full CRUD.
- profiles: GRANT SELECT + UPDATE (display_name) to authenticated;
  no INSERT/DELETE to authenticated. service_role gets full access.
- New trigger function create_profile_on_signup() SECURITY DEFINER, fires AFTER INSERT
  on auth.users, creates profiles row with is_admin=false.
- Backfill: creates profiles for existing auth.users without one.

## Important Notes
1. Clients cannot set amount, discount, payment_status, delivery_status, result,
   user_id, mode, error, or attempts. These are server-controlled.
2. INSERT on orders only accepts product and payload from the client.
   user_id defaults to auth.uid(), amount defaults to 0 (server will set price
   via edge function in the next phase — payments are disabled now).
3. is_admin can ONLY be set via service_role or SQL in the dashboard.
*/

-- === Revoke all existing grants on orders ===
REVOKE SELECT, INSERT, UPDATE, DELETE ON orders FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON orders FROM authenticated;

-- === Re-grant orders: SELECT all columns, INSERT only product+payload ===
GRANT SELECT ON orders TO authenticated;
GRANT INSERT (product, payload) ON orders TO authenticated;

-- service_role for server-side operations
GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO service_role;

-- === Drop old UPDATE and DELETE policies on orders (clients no longer have those grants) ===
DROP POLICY IF EXISTS "update_own_orders" ON orders;
DROP POLICY IF EXISTS "delete_own_orders" ON orders;

-- Keep SELECT and INSERT policies
-- (select_own_orders and insert_own_orders already exist and are correct)

-- === Revoke all existing grants on profiles ===
REVOKE SELECT, INSERT, UPDATE, DELETE ON profiles FROM anon;
REVOKE SELECT, INSERT, UPDATE, DELETE ON profiles FROM authenticated;

-- === Re-grant profiles: SELECT + UPDATE(display_name) only ===
GRANT SELECT ON profiles TO authenticated;
GRANT UPDATE (display_name) ON profiles TO authenticated;

-- service_role for server-side management
GRANT SELECT, INSERT, UPDATE, DELETE ON profiles TO service_role;

-- === Drop old INSERT policy on profiles (clients no longer insert profiles) ===
-- There was no explicit INSERT policy, but drop if exists for safety
DROP POLICY IF EXISTS "insert_own_profile" ON profiles;

-- === Trigger function: create profile on signup ===
CREATE OR REPLACE FUNCTION create_profile_on_signup()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, email, display_name, is_admin)
  VALUES (NEW.id, NEW.email, NULL, false)
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_profile_on_signup() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION create_profile_on_signup() TO authenticated;

-- === Attach trigger to auth.users ===
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION create_profile_on_signup();

-- === Backfill: create profiles for existing auth.users without one ===
INSERT INTO profiles (id, email, is_admin)
SELECT u.id, u.email, false
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;