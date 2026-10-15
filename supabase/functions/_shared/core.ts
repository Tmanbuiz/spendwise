export class ApiError extends Error {
  constructor(public code: string, public status = 500, public retryable = false) { super(code); }
}
export function sinceDate(value: unknown, now = new Date()): string {
  const date = value === undefined ? new Date(now.getTime() - 90 * 86400000) :
    typeof value === 'string' ? new Date(value) : new Date(NaN);
  if (!Number.isFinite(date.getTime()) || date > now || now.getTime() - date.getTime() > 730 * 86400000) {
    throw new ApiError('invalid_since', 400);
  }
  return date.toISOString().slice(0, 10);
}
export async function pages(token: string, since: string, request: (path: string, params: Record<string, unknown>) => Promise<any>) {
  const transactions: any[] = [], accounts: Record<string, string> = {};
  let total = 1;
  while (transactions.length < total) {
    const page = await request('/transactions/get', { access_token: token, start_date: since,
      end_date: new Date().toISOString().slice(0, 10), options: { offset: transactions.length, count: 500 } });
    if (!Array.isArray(page.transactions) || !Number.isSafeInteger(page.total_transactions) || page.total_transactions < 0) {
      throw new ApiError('invalid_provider_response', 502);
    }
    total = page.total_transactions;
    if (page.transactions.length === 0 && transactions.length < total) throw new ApiError('incomplete_sync', 502, true);
    for (const a of page.accounts ?? []) accounts[a.account_id] = a.mask ?? '';
    transactions.push(...page.transactions);
    if (transactions.length > 100000) throw new ApiError('sync_limit', 502);
  }
  return { transactions, accounts };
}
