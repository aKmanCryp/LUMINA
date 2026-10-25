-- Drop old function overloads that lack lease_token parameter
DROP FUNCTION IF EXISTS public.complete_generation(uuid, jsonb, text, int, int, int, text);
DROP FUNCTION IF EXISTS public.fail_generation(uuid, text);
