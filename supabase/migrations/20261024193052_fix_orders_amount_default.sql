/*
# Fix: orders.amount needs a default value

## Problem
The corrective lockdown restricted INSERT to only (product, payload) columns.
But orders.amount is NOT NULL with no default, so every client INSERT fails
with a constraint violation — orders can't be saved at all.

## Fix
Set DEFAULT 0 on amount. The real price will be set server-side via edge
function in the next phase (payments + IA). A default of 0 is safe because:
1. Clients can't read or write amount beyond SELECT (RLS + column grants).
2. Orders with amount=0 are clearly placeholder — payment_status stays 'pending'.
3. The order is saved so the user can see it in "Mis lecturas".

This is a column default change, not a type change — no data loss.
*/

ALTER TABLE orders ALTER COLUMN amount SET DEFAULT 0;