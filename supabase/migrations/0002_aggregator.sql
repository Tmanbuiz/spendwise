-- Bank connections made through a data aggregator (Plaid, Flinks).
--
-- The security question this table answers: where does the access token live?
-- Answer: here, behind RLS, readable only by Edge Functions acting as the
-- owning user — never sent to the device. A token in an APK would let anyone
-- who extracts it pull the account without the user present.

-- Transactions can now originate from a linked account, not just a
-- notification or manual entry.
alter type transaction_source add value if not exists 'aggregator';

create type aggregator_provider as enum ('plaid', 'flinks');

create table public.linked_items (
  id               spendwise_id        not null,
  user_id          uuid                not null
                     references auth.users(id) on delete cascade
                     default auth.uid(),
  provider         aggregator_provider not null default 'plaid',
  institution_name text                not null,

  -- The aggregator's long-lived credential. Server-side only: the SELECT
  -- policy below is what keeps it out of client queries.
  access_token     text                not null,

  -- The provider's own id for the connection, needed to revoke it.
  provider_item_id text                not null,

  linked_at        timestamptz         not null default now(),
  last_synced_at   timestamptz,

  -- Bank connections expire and need re-authorisation. Surfacing this beats
  -- letting the sync fail silently.
  needs_reauth     boolean             not null default false,

  primary key (user_id, id)
);

create unique index linked_items_provider_item_idx
  on public.linked_items (user_id, provider, provider_item_id);

alter table public.linked_items enable row level security;

-- Note there is no policy granting `authenticated` a SELECT on this table.
-- That is deliberate, not an omission: the app never needs the access token,
-- and the only way to guarantee it cannot leak is to make the row unreadable
-- from the client at all. Edge Functions read it with the service-role key.
--
-- What the app *does* need — which bank, when it synced, whether it needs
-- reauth — is served by the view below, which simply does not select the
-- token column.

create policy "own links insertable"
  on public.linked_items for insert to authenticated
  with check (user_id = auth.uid());
create policy "own links updatable"
  on public.linked_items for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own links deletable"
  on public.linked_items for delete to authenticated
  using (user_id = auth.uid());

-- Token-free projection for the client.
create view public.linked_items_public
with (security_invoker = true)
as
  select id, user_id, provider, institution_name,
         linked_at, last_synced_at, needs_reauth
  from public.linked_items
  where user_id = auth.uid();

grant select on public.linked_items_public to authenticated;

-- Aggregator-sourced transactions carry the provider's id as their
-- fingerprint (prefixed `agg:`), so re-syncing updates in place rather than
-- inserting a duplicate. This index makes that lookup cheap.
create index transactions_user_provider_fingerprint_idx
  on public.transactions (user_id, fingerprint)
  where fingerprint like 'agg:%';
