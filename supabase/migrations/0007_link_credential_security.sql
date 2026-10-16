-- Only trusted Edge Functions may mutate credentials. Clients may select
-- explicitly granted metadata columns; RLS still isolates each owner.
drop policy if exists "own links insertable" on public.linked_items;
drop policy if exists "own links updatable" on public.linked_items;
drop policy if exists "own links deletable" on public.linked_items;
revoke all on public.linked_items from anon, authenticated;
grant select (id, user_id, provider, institution_name, linked_at, last_synced_at, needs_reauth)
  on public.linked_items to authenticated;
create policy "own link metadata readable" on public.linked_items
  for select to authenticated using (user_id = auth.uid());
-- security_invoker view now has both its underlying column grants and RLS.
