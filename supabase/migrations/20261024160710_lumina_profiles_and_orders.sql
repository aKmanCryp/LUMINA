/*
# LÚMINA: profiles, orders tables with RLS and admin role function

## Purpose
Sets up the core database schema for LÚMINA's customer authentication and order isolation.
This migration supports: real customer accounts (email/password via Supabase Auth),
per-user order isolation, and a secure admin role mechanism that users cannot self-assign.

## New Tables

### profiles
- `id` (uuid, primary key, references auth.users) — one row per user account
- `email` (text) — cached email for convenience
- `display_name` (text, nullable) — user-chosen display name
- `is_admin` (boolean, default false) — admin flag; set only via server-side function, never client-writable
- `created_at` (timestamptz)

### orders
- `id` (uuid, primary key)
- `user_id` (uuid, not null, references auth.users, defaults to auth.uid())
- `product` (text, not null) — product id: lectura | compatibilidad | premium
- `amount` (integer, not null) — price in PYG
- `discount` (integer, not null default 0)
- `payload` (jsonb, not null) — validated order input
- `payment_status` (text, not null default 'pending')
- `delivery_status` (text, not null default 'pending')
- `result` (jsonb, nullable) — generated reading
- `created_at` (timestamptz default now())
- `error` (text, nullable)
- `attempts` (integer, not null default 0)
- `mode` (text, not null default 'manual_qr')

## Security Changes

### profiles
- RLS enabled
- GRANT SELECT to authenticated (users can read their own profile)
- GRANT UPDATE (display_name) to authenticated — only display_name is writable, NOT is_admin
- 4 policies: select own, update own (display_name only via column grant), no insert/delete from client

### orders
- RLS enabled
- GRANT SELECT, INSERT, UPDATE to authenticated
- 4 policies: select own, insert own, update own, delete own — all scoped to auth.uid() = user_id
- user_id defaults to auth.uid() so inserts omitting it still pass WITH CHECK

### is_admin() function
- SECURITY DEFINER function that reads the is_admin column from profiles
- EXECUTE granted to authenticated — used by RLS policies on admin-scoped data
- Users cannot set is_admin because the column grant only allows updating display_name

## Important Notes
1. The is_admin column on profiles is NOT writable by clients — the column-level GRANT
   only allows updating display_name. Admin assignment is done via SQL or edge function
   with service_role key, never from the browser.
2. The is_admin() helper function lets RLS policies check admin status without
   exposing the column to client writes.
3. Email confirmation is OFF by default in Supabase Auth — no change needed.
4. No data is imported from the pilot; this is a fresh schema.
*/

-- === profiles table ===
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL,
  display_name text,
  is_admin boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON profiles TO authenticated;
GRANT UPDATE (display_name) ON profiles TO authenticated;

DROP POLICY IF EXISTS "select_own_profile" ON profiles;
CREATE POLICY "select_own_profile"
  ON profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "update_own_profile" ON profiles;
CREATE POLICY "update_own_profile"
  ON profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- === orders table ===
CREATE TABLE IF NOT EXISTS orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  product text NOT NULL,
  amount integer NOT NULL,
  discount integer NOT NULL DEFAULT 0,
  payload jsonb NOT NULL,
  payment_status text NOT NULL DEFAULT 'pending',
  delivery_status text NOT NULL DEFAULT 'pending',
  result jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  error text,
  attempts integer NOT NULL DEFAULT 0,
  mode text NOT NULL DEFAULT 'manual_qr'
);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON orders TO authenticated;

DROP POLICY IF EXISTS "select_own_orders" ON orders;
CREATE POLICY "select_own_orders"
  ON orders FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "insert_own_orders" ON orders;
CREATE POLICY "insert_own_orders"
  ON orders FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "update_own_orders" ON orders;
CREATE POLICY "update_own_orders"
  ON orders FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "delete_own_orders" ON orders;
CREATE POLICY "delete_own_orders"
  ON orders FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- === is_admin() helper function for RLS ===
-- SECURITY DEFINER so it can read profiles even if future policies tighten access.
-- Returns true if the calling user has is_admin = true in profiles.
CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
    AND profiles.is_admin = true
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION is_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION is_admin() TO authenticated;

-- === Index for orders by user ===
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);
