/*
# Fix cron job URL/secret construction from JSONB app_settings

## Problem
The cron job reads `project_url` and `cron_secret` from `app_settings` using
`value::text`. Since `app_settings.value` is a JSONB column, `value::text`
returns the value WITH surrounding double-quotes and escaped quotes inside,
e.g. `"pbxkpvjeznpavpxdxlma.supabase.co"` (with literal quote characters).

This produces invalid URLs like:
  https://"pbxkpvjeznpavpxdxlma.supabase.co"/functions/v1/process-queue
and invalid secret headers with extra quotes.

The cron job has been firing every 2 minutes (verified in net._http_response)
but every call failed with "SSL peer certificate or SSH remote key was not OK"
because the URL was malformed.

## Fix
1. Reschedule the cron job using `#>>` operator to extract the text value
   from JSONB without quotes: `value #>> '{}'` returns the raw string.
2. Apply the same fix to the cron_secret extraction.

## Important notes
- The cron job schedule (every 2 minutes) and name are unchanged.
- The old job is unscheduled first, then recreated.
*/

SELECT cron.unschedule('process-generation-queue');

SELECT cron.schedule(
  'process-generation-queue',
  '*/2 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://' || COALESCE(
      (SELECT value #>> '{}' FROM app_settings WHERE key = 'project_url'),
      'localhost'
    ) || '/functions/v1/process-queue',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'X-Cron-Secret', COALESCE(
        (SELECT value #>> '{}' FROM app_settings WHERE key = 'cron_secret'),
        ''
      )
    ),
    body := '{}'::jsonb
  )
  $cron$
);