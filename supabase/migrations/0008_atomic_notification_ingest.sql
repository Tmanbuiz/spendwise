-- Serialize notification deduplication across devices and overlapping requests.
-- Invoker security and explicit auth.uid() keep ordinary table RLS in force.
create or replace function public.ingest_notification(payload jsonb, duplicate_seconds integer default 600)
returns void language plpgsql security invoker set search_path = public, pg_temp as $$
declare
  owner_id uuid := auth.uid();
  incoming public.transactions;
  window_seconds integer := least(14400, greatest(60, coalesce(duplicate_seconds, 600)));
begin
  if owner_id is null then raise insufficient_privilege using message = 'Authentication required'; end if;
  if octet_length(payload::text) > 64000 then raise exception 'Payload too large'; end if;
  incoming := jsonb_populate_record(null::public.transactions, payload || jsonb_build_object('user_id', owner_id));
  if incoming.source <> 'notification' or incoming.fingerprint is null or incoming.occurred_at is null then
    raise exception 'Invalid notification';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':' || incoming.fingerprint || ':' ||
    coalesce(incoming.bank_id, '') || ':' || coalesce(incoming.account_last4, ''), 0));
  -- Edits to an existing ID remain possible. A replay with a new ID must
  -- pass a storage-authoritative check inside this same transaction.
  if not exists (select 1 from public.transactions where user_id = owner_id and id = incoming.id)
    and exists (select 1 from public.transactions t where t.user_id = owner_id
      and t.fingerprint = incoming.fingerprint and t.bank_id is not distinct from incoming.bank_id
      and t.account_last4 is not distinct from incoming.account_last4
      and t.occurred_at between incoming.occurred_at - make_interval(secs => window_seconds)
                            and incoming.occurred_at + make_interval(secs => window_seconds)) then
    return;
  end if;
  insert into public.transactions (id, user_id, event_type, amount_cents, currency, occurred_at, category,
    source, merchant, merchant_normalized, account_id, account_label, account_last4, bank_id, note,
    fingerprint, needs_review, excluded_by_user, category_set_by_user, direction)
  values (incoming.id, owner_id, incoming.event_type, incoming.amount_cents, incoming.currency,
    incoming.occurred_at, incoming.category, incoming.source, incoming.merchant, incoming.merchant_normalized,
    incoming.account_id, incoming.account_label, incoming.account_last4, incoming.bank_id, incoming.note,
    incoming.fingerprint, incoming.needs_review, incoming.excluded_by_user, incoming.category_set_by_user, incoming.direction)
  on conflict (user_id, id) do update set event_type=excluded.event_type, amount_cents=excluded.amount_cents,
    currency=excluded.currency, occurred_at=excluded.occurred_at, category=excluded.category, source=excluded.source,
    merchant=excluded.merchant, merchant_normalized=excluded.merchant_normalized, account_id=excluded.account_id,
    account_label=excluded.account_label, account_last4=excluded.account_last4, bank_id=excluded.bank_id,
    note=excluded.note, fingerprint=excluded.fingerprint, needs_review=excluded.needs_review,
    excluded_by_user=excluded.excluded_by_user, category_set_by_user=excluded.category_set_by_user, direction=excluded.direction;
end;
$$;
revoke all on function public.ingest_notification(jsonb, integer) from public, anon;
grant execute on function public.ingest_notification(jsonb, integer) to authenticated;
