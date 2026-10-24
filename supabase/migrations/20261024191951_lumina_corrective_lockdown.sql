/*
# Corrective migration: lock down order columns, add profile trigger, remove anon grants

## Problems Fixed

1. **orders: clients could UPDATE any column** — The previous migration granted
   UPDATE on all columns. A client could change `amount`, `discount`,
   `payment_status`, `delivery_status`, `result`, `user_id`, or `mode` directly.
   This migration revokes the broad grant and replaces it with a column-restricted
   grant that only allows updating nothing (orders are created server-side;
   clients should not update orders at all in this phase). The UPDATE policy is
   kept but the column grant makes it impossible to change protected columns.

2. **orders: clients could INSERT any column values** — The INSERT grant allowed
   setting arbitrary amounts, statuses, and results. This revokes the broad grant
   and re-grants INSERT on only the columns a client legitimately provides:
   `product`, `payload`. All other columns use database defaults (amount is not
   yet server-enforced via a function, so for now INSERT is restricted to product
   and payload only; the price must be set by server logic — in this phase, orders
   are created but payments are disabled).

3. **profiles: no auto-creation on signup** — The client tried to upsert into
   profiles, which could fail silently. This adds a trigger on auth.users that
   creates a profile row with is_admin=false whenever a new user signs up.
   The client no longer needs to write to profiles at all.

4. **profiles: anon had full CRUD** — Revoked all grants from anon on both tables.
   Only authenticated users get access, scoped by RLS.

5. **is_admin column protection** — The column-level GRANT on profiles only allows
   updating `display_name`. Even if a user somehow sends is_admin=true in an
   update, the database rejects it because there is no grant for that column.

## Changes

### GRANT changes on orders
- REVOKE all from anon and authenticated
- GRANT SELECT to authenticated (all columns — needed to read own orders)
- GRANT INSERT (product, payload) to authenticated — only these client-settable columns
- No UPDATE or DELETE grant to authenticated (orders are immutable from the client)
- GRANT SELECT, INSERT, UPDATE, DELETE to service_role for server-side operations

### GRANT changes on profiles
- REVOKE all from anon
- GRANT SELECT to authenticated
- GRANT UPDATE (display_name) to authenticated — ONLY display_name, NOT is_admin
- GRANT INSERT, UPDATE to service_role for server-side management

### Trigger: create_profile_on_signup
- AFTER INSERT on auth.users
- Creates a profiles row with id, email, is_admin=false
- SECURITY DEFINER function so it can write to profiles even with RLS

### Backfill
- Creates profiles for any existing auth.users that don't have one yet
- Sets is_admin=false, preserves existing roles

## Important Notes
1. Clients can no longer set amount, discount, payment_status, delivery_status,
   result, user_id, mode, error, or attempts on orders. These are server-controlled.
2. The INSERT on orders only accepts product and payload from the client.
   Amount defaults to 0 (placeholder until server-side price enforcement is added
   with edge functions in the next phase). The RLS insert policy still checks
   user_id ownership via the DEFAULT auth.uid().
3. is_admin can ONLY be set by service_role (server-side) or by SQL in the
   Supabase dashboard. No client API call can set it.
4. The trigger ensures every new signup gets a profile automatically — the
   client-side upsert is no longer needed.
*/