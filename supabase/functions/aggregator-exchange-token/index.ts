import { ApiError, body, endpoint, plaid, publicItem } from '../_shared/aggregator.ts';
Deno.serve(endpoint(async (req, { user, admin }) => {
  const { public_token } = await body(req);
  if (typeof public_token !== 'string' || !public_token || public_token.length > 4096) throw new ApiError('invalid_token', 400);
  const exchanged = await plaid('/item/public_token/exchange', { public_token });
  try {
    const info = await plaid('/item/get', { access_token: exchanged.access_token });
    let name = 'Linked bank';
    if (info.item?.institution_id) {
      const institution = await plaid('/institutions/get_by_id', { institution_id: info.item.institution_id, country_codes: ['CA'] });
      name = institution.institution?.name ?? name;
    }
    const { data, error } = await admin.from('linked_items').upsert({ id: crypto.randomUUID(), user_id: user.id,
      provider: 'plaid', access_token: exchanged.access_token, provider_item_id: exchanged.item_id,
      institution_name: name, needs_reauth: false }, { onConflict: 'user_id,provider,provider_item_id' })
      .select('id, provider, institution_name, linked_at, last_synced_at, needs_reauth').single();
    if (error || !data) throw new ApiError('link_save_failed');
    return publicItem(data);
  } catch (e) {
    // A failed exchange must not leave an untracked provider credential active.
    await plaid('/item/remove', { access_token: exchanged.access_token }).catch(() => {});
    throw e;
  }
}));
