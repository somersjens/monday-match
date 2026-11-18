-- Stop Swiping: runs push-dispatch from pg_cron.
--
-- Runs after 202611160002_push_notifications.sql and the push-dispatch edge
-- function. Safe before APNs is configured: the job only calls the function
-- once the dispatch secret is in Vault and a push is actually due, so an idle
-- project makes no function calls at all (instead of one every 15 seconds).
--
-- Still to do by hand, see docs/notifications.md:
--   select vault.create_secret('<PUSH_DISPATCH_SECRET>', 'push_dispatch_secret');
-- plus the function secrets APNS_KEY_ID, APNS_PRIVATE_KEY and
-- PUSH_DISPATCH_SECRET, and "Verify JWT with legacy secret" off for push-dispatch.
begin;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

-- Scheduling under an existing name replaces that job.
select cron.schedule('push-dispatch', '15 seconds', $job$
    select net.http_post(
        url := 'https://yrnwzehdzlxwnhyabwja.supabase.co/functions/v1/push-dispatch',
        headers := jsonb_build_object('Content-Type', 'application/json',
            'X-Dispatch-Secret', (select decrypted_secret from vault.decrypted_secrets
                where name = 'push_dispatch_secret')),
        body := '{}'::jsonb, timeout_milliseconds := 10000)
    where exists (select 1 from vault.decrypted_secrets where name = 'push_dispatch_secret')
        and exists (select 1 from notification_private.outbox
            where sent_at is null and not_before <= now()
                and (claimed_at is null or (claimed_at < now() - interval '5 minutes' and attempts < 5)));
$job$);

-- History older than two weeks, and pg_cron's own run log, which otherwise
-- grows by thousands of rows a day.
select cron.schedule('push-prune', '41 3 * * *', $job$
    select notification_private.prune_outbox();
    delete from cron.job_run_details where end_time < now() - interval '7 days';
$job$);

commit;
