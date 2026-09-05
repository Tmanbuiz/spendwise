-- SpendWise initial schema.
--
-- Two rules shape every table here:
--
--   1. `user_id` is never sent by the client. It defaults to `auth.uid()` and
--      RLS enforces it, so a client bug cannot write a row that belongs to
--      someone else, and cannot read one either.
--
--   2. No column exists for a banking password, PIN, CVV or full card number.
--      There is nowhere to put one. The most a card contributes is
--      `account_last4`, constrained to exactly four digits.

-- ---------------------------------------------------------------- extensions
create extension if not exists "pgcrypto";

-- ------------------------------------------------------------------- helpers

-- Ids are generated on the device so a transaction exists before it reaches
-- the network. They are opaque strings, not uuids.
create domain spendwise_id as text
  check (value ~ '^[A-Za-z0-9_-]{1,64}$');

create domain money_cents as bigint
  check (value >= 0);

-- Direction of money movement is carried by event_type, never by a sign, so
-- amounts are non-negative everywhere.

create type transaction_event_type as enum (
  'purchase',
  'refund',
  'payment',
  'transfer',
  'declined',
  'unknown'
);

create type transaction_source as enum (
  'notification',
  'manual',
  'email'          -- reserved for the planned iOS email importer
);

create type spend_category as enum (
  'groceries',
  'dining',
  'gas',
  'transportation',
  'shopping',
  'utilities',
  'phone_internet',
  'subscriptions',
  'housing',
  'health',
  'entertainment',
  'other'
);

create type rule_match_type as enum (
  'exact',
  'contains',
  'startsWith',
  'regex'
);

create type rule_source as enum ('builtIn', 'user');

-- --------------------------------------------------------- user_preferences

create table public.user_preferences (
  user_id                       uuid primary key
                                  references auth.users(id) on delete cascade
                                  default auth.uid(),
  selected_bank_ids             text[]      not null default '{}',
  onboarding_complete           boolean     not null default false,
  notification_access_confirmed boolean     not null default false,
  currency                      text        not null default 'CAD'
                                  check (currency ~ '^[A-Z]{3}$'),
  month_start_day               smallint    not null default 1
                                  check (month_start_day between 1 and 28),
  auto_categorize               boolean     not null default true,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now()
);

-- ------------------------------------------------------------------ accounts

create table public.accounts (
  id          spendwise_id not null,
  user_id     uuid         not null
                references auth.users(id) on delete cascade
                default auth.uid(),
  bank_id     text         not null,
  label       text         not null,
  -- The ONLY card data stored anywhere. Exactly four digits or nothing.
  last4       text         check (last4 ~ '^[0-9]{4}$'),
  type        text         not null default 'unknown',
  is_archived boolean      not null default false,
  created_at  timestamptz  not null default now(),
  primary key (user_id, id)
);

-- -------------------------------------------------------------- transactions

create table public.transactions (
  id                   spendwise_id           not null,
  user_id              uuid                   not null
                         references auth.users(id) on delete cascade
                         default auth.uid(),
  event_type           transaction_event_type not null,
  amount_cents         money_cents            not null,
  currency             text                   not null default 'CAD'
                         check (currency ~ '^[A-Z]{3}$'),
  occurred_at          timestamptz            not null,
  category             spend_category         not null default 'other',
  source               transaction_source     not null default 'notification',
  merchant             text,
  merchant_normalized  text,
  account_id           spendwise_id,
  account_label        text,
  account_last4        text check (account_last4 ~ '^[0-9]{4}$'),
  bank_id              text,
  note                 text,
  -- Content identity used for duplicate suppression. Time is deliberately not
  -- part of it; the client applies a time window instead.
  fingerprint          text,
  needs_review         boolean                not null default false,
  excluded_by_user     boolean                not null default false,
  category_set_by_user boolean                not null default false,
  created_at           timestamptz            not null default now(),
  updated_at           timestamptz            not null default now(),
  primary key (user_id, id),
  foreign key (user_id, account_id)
    references public.accounts(user_id, id) on delete set null
);

-- The dashboard always queries "my rows, in this month, newest first".
create index transactions_user_occurred_idx
  on public.transactions (user_id, occurred_at desc);

-- Supports duplicate lookups when the client warms up after a restart.
create index transactions_user_fingerprint_idx
  on public.transactions (user_id, fingerprint)
  where fingerprint is not null;

-- Supports "everything from this merchant", used by the rules editor.
create index transactions_user_merchant_idx
  on public.transactions (user_id, merchant_normalized)
  where merchant_normalized is not null;

-- ------------------------------------------------------------------- budgets

create table public.budgets (
  id           spendwise_id   not null,
  user_id      uuid           not null
                 references auth.users(id) on delete cascade
                 default auth.uid(),
  -- Null means the overall monthly budget.
  category     spend_category,
  amount_cents money_cents    not null,
  currency     text           not null default 'CAD'
                 check (currency ~ '^[A-Z]{3}$'),
  created_at   timestamptz    not null default now(),
  primary key (user_id, id)
);

-- One budget per category, and exactly one overall budget. Two partial indexes
-- rather than one constraint, because Postgres treats NULLs as distinct and a
-- plain unique(user_id, category) would allow unlimited overall budgets.
create unique index budgets_one_per_category_idx
  on public.budgets (user_id, category)
  where category is not null;

create unique index budgets_one_overall_idx
  on public.budgets (user_id)
  where category is null;

-- ------------------------------------------------------------ merchant_rules

create table public.merchant_rules (
  id         spendwise_id    not null,
  user_id    uuid            not null
               references auth.users(id) on delete cascade
               default auth.uid(),
  pattern    text            not null check (length(pattern) between 2 and 200),
  category   spend_category  not null,
  match_type rule_match_type not null default 'contains',
  source     rule_source     not null default 'user',
  created_at timestamptz     not null default now(),
  primary key (user_id, id)
);

create unique index merchant_rules_unique_pattern_idx
  on public.merchant_rules (user_id, upper(pattern), match_type);

-- ---------------------------------------------------------- unparsed_samples
--
-- Redacted notification text kept ONLY when a parse was incomplete, so parser
-- coverage can be improved. Every digit is masked before it is written, and
-- rows expire — see the purge function below.

create table public.unparsed_samples (
  id           spendwise_id not null,
  user_id      uuid         not null
                 references auth.users(id) on delete cascade
                 default auth.uid(),
  bank_id      text         not null,
  redacted_raw text         not null
                 -- Belt and braces: reject anything that still has a digit.
                 check (redacted_raw !~ '[0-9]'),
  parse_gaps   text[]       not null default '{}',
  created_at   timestamptz  not null default now(),
  expires_at   timestamptz  not null default now() + interval '30 days',
  primary key (user_id, id)
);

create index unparsed_samples_expiry_idx
  on public.unparsed_samples (expires_at);

-- ------------------------------------------------------------- updated_at

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger transactions_touch_updated_at
  before update on public.transactions
  for each row execute function public.touch_updated_at();

create trigger user_preferences_touch_updated_at
  before update on public.user_preferences
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------- Row Level Security
--
-- Enabled on every table, with an explicit policy per operation rather than
-- one FOR ALL policy. Separating them means the WITH CHECK on insert and
-- update is stated in full: a client cannot insert a row for another user,
-- and cannot update one of its own rows into belonging to someone else.

alter table public.user_preferences enable row level security;
alter table public.accounts         enable row level security;
alter table public.transactions     enable row level security;
alter table public.budgets          enable row level security;
alter table public.merchant_rules   enable row level security;
alter table public.unparsed_samples enable row level security;

-- Deny anonymous access outright; every policy below is for authenticated
-- users acting on their own rows.

create policy "own preferences readable"
  on public.user_preferences for select to authenticated
  using (user_id = auth.uid());
create policy "own preferences insertable"
  on public.user_preferences for insert to authenticated
  with check (user_id = auth.uid());
create policy "own preferences updatable"
  on public.user_preferences for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own preferences deletable"
  on public.user_preferences for delete to authenticated
  using (user_id = auth.uid());

create policy "own accounts readable"
  on public.accounts for select to authenticated
  using (user_id = auth.uid());
create policy "own accounts insertable"
  on public.accounts for insert to authenticated
  with check (user_id = auth.uid());
create policy "own accounts updatable"
  on public.accounts for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own accounts deletable"
  on public.accounts for delete to authenticated
  using (user_id = auth.uid());

create policy "own transactions readable"
  on public.transactions for select to authenticated
  using (user_id = auth.uid());
create policy "own transactions insertable"
  on public.transactions for insert to authenticated
  with check (user_id = auth.uid());
create policy "own transactions updatable"
  on public.transactions for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own transactions deletable"
  on public.transactions for delete to authenticated
  using (user_id = auth.uid());

create policy "own budgets readable"
  on public.budgets for select to authenticated
  using (user_id = auth.uid());
create policy "own budgets insertable"
  on public.budgets for insert to authenticated
  with check (user_id = auth.uid());
create policy "own budgets updatable"
  on public.budgets for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own budgets deletable"
  on public.budgets for delete to authenticated
  using (user_id = auth.uid());

create policy "own rules readable"
  on public.merchant_rules for select to authenticated
  using (user_id = auth.uid());
create policy "own rules insertable"
  on public.merchant_rules for insert to authenticated
  with check (user_id = auth.uid());
create policy "own rules updatable"
  on public.merchant_rules for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own rules deletable"
  on public.merchant_rules for delete to authenticated
  using (user_id = auth.uid());

create policy "own samples readable"
  on public.unparsed_samples for select to authenticated
  using (user_id = auth.uid());
create policy "own samples insertable"
  on public.unparsed_samples for insert to authenticated
  with check (user_id = auth.uid());
create policy "own samples deletable"
  on public.unparsed_samples for delete to authenticated
  using (user_id = auth.uid());
-- Deliberately no UPDATE policy: a retained sample is written once and then
-- either read or purged. Nothing should rewrite it.

-- --------------------------------------------------------------- bootstrap
--
-- Give every new user a preferences row, so the app never has to distinguish
-- "no row yet" from "row with defaults".

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.user_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------- purge
--
-- Retention is enforced server-side as well as client-side, so an old sample
-- expires even if the device that wrote it never comes back.
--
-- Schedule with pg_cron:
--   select cron.schedule(
--     'purge-unparsed-samples', '0 3 * * *',
--     $$select public.purge_expired_samples()$$
--   );

create or replace function public.purge_expired_samples()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  removed integer;
begin
  delete from public.unparsed_samples where expires_at < now();
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.purge_expired_samples() from public;
