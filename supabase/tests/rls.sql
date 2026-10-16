\set ON_ERROR_STOP on
begin;
insert into auth.users(id) values ('11111111-1111-1111-1111-111111111111'), ('22222222-2222-2222-2222-222222222222');
insert into public.linked_items(id,user_id,institution_name,access_token,provider_item_id)
values ('a','11111111-1111-1111-1111-111111111111','A bank','secret-a','provider-a'),
('b','22222222-2222-2222-2222-222222222222','B bank','secret-b','provider-b');
insert into storage.objects(bucket_id,name) values
('financial-documents','11111111-1111-1111-1111-111111111111/a/file.pdf'),
('financial-documents','22222222-2222-2222-2222-222222222222/b/file.pdf');
set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-1111-1111-111111111111',true);
do $$ begin
  if (select count(*) from public.linked_items_public) <> 1 then raise exception 'Owner isolation failed'; end if;
  if (select id from public.linked_items_public) <> 'a' then raise exception 'Wrong owner'; end if;
  if (select count(*) from storage.objects where bucket_id='financial-documents') <> 1 then raise exception 'Storage isolation failed'; end if;
  begin
    perform access_token from public.linked_items;
    raise exception 'Token SELECT unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  begin
    update public.linked_items set access_token='attacker';
    raise exception 'Credential UPDATE unexpectedly allowed';
  exception when insufficient_privilege then null; end;
  begin
    delete from public.linked_items where id='b';
    raise exception 'Client DELETE unexpectedly allowed';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claim.sub','22222222-2222-2222-2222-222222222222',true);
do $$ begin
  if (select count(*) from public.linked_items_public) <> 1 or (select id from public.linked_items_public) <> 'b' then raise exception 'Second owner isolation failed'; end if;
end $$;
-- The same captured event replayed under a second client ID remains one row.
select public.ingest_notification('{"id":"event-a","source":"notification","event_type":"purchase",
  "amount_cents":1200,"currency":"CAD","occurred_at":"2026-10-15T10:00:00Z","category":"other",
  "bank_id":"cibc","account_last4":"1234","fingerprint":"alert","needs_review":false,
  "excluded_by_user":false,"category_set_by_user":false}'::jsonb);
select public.ingest_notification('{"id":"event-b","source":"notification","event_type":"purchase",
  "amount_cents":1200,"currency":"CAD","occurred_at":"2026-10-15T10:00:00Z","category":"other",
  "bank_id":"cibc","account_last4":"1234","fingerprint":"alert","needs_review":false,
  "excluded_by_user":false,"category_set_by_user":false}'::jsonb);
do $$ begin
  if (select count(*) from public.transactions where fingerprint='alert') <> 1 then
    raise exception 'Notification replay created a duplicate';
  end if;
end $$;
rollback;
