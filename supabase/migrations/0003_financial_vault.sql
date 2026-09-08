-- Financial vault + persistent financial memory.
--
-- The vault stores document metadata in Postgres and the source bytes in a
-- private Supabase Storage bucket. Object names are always prefixed with the
-- authenticated user's id, and both table RLS and Storage policies enforce
-- that boundary.

-- -------------------------------------------------------- financial_documents
create table public.financial_documents (
  id                         spendwise_id not null,
  user_id                    uuid         not null
                               references auth.users(id) on delete cascade
                               default auth.uid(),
  file_name                  text         not null
                               check (length(file_name) between 1 and 255),
  storage_path               text         not null
                               check (length(storage_path) between 1 and 1024),
  storage_kind               text         not null
                               check (storage_kind in ('local', 'supabase')),
  document_type              text         not null
                               check (document_type in (
                                 'bankStatement',
                                 'creditCardStatement',
                                 'payStub',
                                 'investmentStatement',
                                 'taxDocument',
                                 'receipt',
                                 'other'
                               )),
  added_at                   timestamptz  not null default now(),
  mime_type                  text,
  size_bytes                 bigint       not null default 0
                               check (size_bytes >= 0),
  institution                text,
  owner_label                text,
  account_label              text,
  account_last4              text check (account_last4 ~ '^[0-9]{4}$'),
  period_start               date,
  period_end                 date,
  imported_transaction_count integer      not null default 0
                               check (imported_transaction_count >= 0),
  note                       text,
  created_at                 timestamptz  not null default now(),
  updated_at                 timestamptz  not null default now(),
  primary key (user_id, id),
  check (period_end is null or period_start is null or period_end >= period_start)
);

create index financial_documents_user_added_idx
  on public.financial_documents (user_id, added_at desc);

create index financial_documents_user_period_idx
  on public.financial_documents (user_id, period_start, period_end);

create trigger financial_documents_touch_updated_at
  before update on public.financial_documents
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------ financial_rules
--
-- These are distinct from merchant category rules. Category rules answer
-- "which expense category?" while financial rules answer the more fundamental
-- question "is this spending, income, investing, an internal transfer, or an
-- item the user wants ignored?".
create table public.financial_rules (
  id          spendwise_id not null,
  user_id     uuid         not null
                references auth.users(id) on delete cascade
                default auth.uid(),
  pattern     text         not null check (length(pattern) between 2 and 200),
  kind        text         not null
                check (kind in (
                  'expense',
                  'investment',
                  'income',
                  'internalTransfer',
                  'exclude'
                )),
  match_type  text         not null default 'contains'
                check (match_type in ('contains', 'exact', 'startsWith', 'regex')),
  owner_label text,
  note        text,
  enabled     boolean      not null default true,
  created_at  timestamptz  not null default now(),
  updated_at  timestamptz  not null default now(),
  primary key (user_id, id)
);

create unique index financial_rules_unique_pattern_idx
  on public.financial_rules (user_id, upper(pattern), match_type);

create trigger financial_rules_touch_updated_at
  before update on public.financial_rules
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------- Row Level Security
alter table public.financial_documents enable row level security;
alter table public.financial_rules     enable row level security;

create policy "own financial documents readable"
  on public.financial_documents for select to authenticated
  using (user_id = auth.uid());
create policy "own financial documents insertable"
  on public.financial_documents for insert to authenticated
  with check (user_id = auth.uid());
create policy "own financial documents updatable"
  on public.financial_documents for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own financial documents deletable"
  on public.financial_documents for delete to authenticated
  using (user_id = auth.uid());

create policy "own financial rules readable"
  on public.financial_rules for select to authenticated
  using (user_id = auth.uid());
create policy "own financial rules insertable"
  on public.financial_rules for insert to authenticated
  with check (user_id = auth.uid());
create policy "own financial rules updatable"
  on public.financial_rules for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "own financial rules deletable"
  on public.financial_rules for delete to authenticated
  using (user_id = auth.uid());

-- ------------------------------------------------------------- file storage
-- Private bucket. The app never makes a public URL for financial documents.
insert into storage.buckets (id, name, public)
values ('financial-documents', 'financial-documents', false)
on conflict (id) do update set public = false;

-- Every object path is: <auth.uid()>/<document-id>/<safe-file-name>
create policy "own vault objects readable"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'financial-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own vault objects insertable"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'financial-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own vault objects updatable"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'financial-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'financial-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own vault objects deletable"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'financial-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
