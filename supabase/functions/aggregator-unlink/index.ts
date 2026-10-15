import { ApiError, body, endpoint, plaid } from '../_shared/aggregator.ts';
Deno.serve(endpoint(async (req, { user, admin }) => {
  const { item_id } = await body(req);
  if (typeof item_id !== 'string' || !item_id || item_id.length > 200) throw new ApiError('invalid_item', 400);
  const { data: item, error } = await admin.from('linked_items').select('access_token')
    .eq('user_id', user.id).eq('id', item_id).maybeSingle();
  if (error) throw new ApiError('links_unavailable');
  if (!item) throw new ApiError('item_not_found', 404);
  await plaid('/item/remove', { access_token: item.access_token });
  const { error: deleted } = await admin.from('linked_items').delete().eq('user_id', user.id).eq('id', item_id);
  if (deleted) throw new ApiError('unlink_save_failed');
  return { unlinked: true };
}));
