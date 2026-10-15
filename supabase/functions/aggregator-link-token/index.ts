import { endpoint, plaid } from '../_shared/aggregator.ts';
Deno.serve(endpoint(async (_req, { user }) => {
  const result = await plaid('/link/token/create', { user: { client_user_id: user.id },
    client_name: 'SpendWise', products: ['transactions'], country_codes: ['CA'], language: 'en',
    ...(Deno.env.get('PLAID_ANDROID_PACKAGE_NAME') ? { android_package_name: Deno.env.get('PLAID_ANDROID_PACKAGE_NAME') } : {}),
    ...(Deno.env.get('PLAID_REDIRECT_URI') ? { redirect_uri: Deno.env.get('PLAID_REDIRECT_URI') } : {}),
  });
  return { link_token: result.link_token };
}));
