-- Records which way the money moved.
--
-- `transaction_event_type` says what a line means, not which way it went: an
-- Interac e-Transfer sent to a friend and a deposit received from an employer
-- are both `transfer`. That was enough while the app only ever reported
-- spending, and stopped being enough the moment it had to report income too —
-- without this column every deposit and every payment out look identical.
--
-- Nullable on purpose, and with no default. A row written before this
-- migration genuinely does not know its direction, and null says so; the
-- client infers a direction for those from the event type instead. Defaulting
-- them to 'outbound' would turn a guess made today into a fact the bank never
-- stated, and there would be no way to tell the two apart later when the
-- inference improves.
--
-- 0001_init.sql is not edited: it has already been applied wherever this
-- project runs, and rewriting an applied migration means the schema in the
-- repository stops matching the database it produced.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'transaction_direction')
  then
    create type transaction_direction as enum ('inbound', 'outbound');
  end if;
end
$$;

alter table public.transactions
  add column if not exists direction transaction_direction;

comment on column public.transactions.direction is
  'Which way the money moved, when the source knew. Null means the source '
  'never said, and the client infers it from event_type.';
