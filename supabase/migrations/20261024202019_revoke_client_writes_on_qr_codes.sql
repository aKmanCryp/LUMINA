-- All legitimate writes to qr_codes go through admin_upload_qr / admin_disable_qr,
-- which run as the definer. Clients keep SELECT (the admin panel lists the slots
-- through the is_admin() policies) and lose the write verbs they never use.
REVOKE INSERT, UPDATE, DELETE ON public.qr_codes FROM authenticated;
REVOKE SELECT, INSERT, UPDATE, DELETE ON public.qr_codes FROM anon;
GRANT SELECT ON public.qr_codes TO authenticated;
