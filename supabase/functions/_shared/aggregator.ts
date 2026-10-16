import { ApiError } from './core.ts';
export { ApiError, sinceDate, pages } from './core.ts';
import { createClient } from 'jsr:@supabase/supabase-js@2';

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: {
    'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  } });
}
export function endpoint(action: (req: Request, ctx: Awaited<ReturnType<typeof authenticate>>) => Promise<unknown>) {
  return async (req: Request) => {
    if (req.method === 'OPTIONS') return json({});
    if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
    try { return json(await action(req, await authenticate(req))); }
    catch (e) {
      const error = e instanceof ApiError ? e : new ApiError('request_failed');
      return json({ error: error.code, retryable: error.retryable }, error.status);
    }
  };
}
async function authenticate(req: Request) {
  const authorization = req.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) throw new ApiError('unauthorized', 401);
  const auth = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: authorization } }, auth: { persistSession: false },
  });
  const { data: { user }, error } = await auth.auth.getUser();
  if (error || !user) throw new ApiError('unauthorized', 401);
  const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return { user, admin };
}
export async function body(req: Request): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.length > 16000) throw new ApiError('body_too_large', 413);
  try {
    const value = text ? JSON.parse(text) : {};
    if (!value || Array.isArray(value) || typeof value !== 'object') throw Error();
    return value;
  } catch { throw new ApiError('invalid_json', 400); }
}
export async function plaid(path: string, params: Record<string, unknown>, fetcher = fetch) {
  const hosts: Record<string, string> = { sandbox: 'https://sandbox.plaid.com', production: 'https://production.plaid.com' };
  const host = hosts[Deno.env.get('PLAID_ENV') ?? 'sandbox'];
  const client_id = Deno.env.get('PLAID_CLIENT_ID'), secret = Deno.env.get('PLAID_SECRET');
  if (!host || !client_id || !secret) throw new ApiError('provider_not_configured', 503);
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await fetcher(`${host}${path}`, { method: 'POST',
        headers: { 'Content-Type': 'application/json' }, signal: AbortSignal.timeout(20000),
        body: JSON.stringify({ ...params, client_id, secret }),
      });
      const payload = await response.json();
      if (response.ok) return payload;
      const retryable = response.status === 429 || response.status >= 500;
      // Never pass provider response bodies or credentials into errors/logs.
      const code = payload.error_code === 'ITEM_LOGIN_REQUIRED' ? 'reauth_required' : 'provider_failed';
      if (!retryable || attempt === 2) throw new ApiError(code, 502, retryable);
    } catch (e) {
      if (e instanceof ApiError) throw e;
      if (attempt === 2) throw new ApiError('provider_unavailable', 502, true);
    }
    await new Promise(resolve => setTimeout(resolve, 250 * 2 ** attempt));
  }
  throw new ApiError('provider_failed', 502, true);
}
export function publicItem(item: Record<string, unknown>) {
  const { id, provider, institution_name, linked_at, last_synced_at, needs_reauth } = item;
  return { id, provider, institution_name, linked_at, last_synced_at, needs_reauth };
}
