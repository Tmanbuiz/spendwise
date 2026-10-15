// Pulls transactions from the aggregator and normalises them for SpendWise.
//
// This runs server-side for one reason above all: PLAID_SECRET grants the
// ability to read a linked bank account without the user present. It must
// never reach the device, where anyone can pull it out of the APK. The client
// only ever sees short-lived link tokens and the normalised rows below.
//
// Deploy:  supabase functions deploy aggregator-sync
// Secrets: supabase secrets set PLAID_CLIENT_ID=... PLAID_SECRET=... \
//                               PLAID_ENV=sandbox

import { ApiError, body, endpoint, pages, plaid, sinceDate } from '../_shared/aggregator.ts';

interface PlaidTransaction {
  transaction_id: string;
  account_id: string;
  amount: number;
  iso_currency_code: string | null;
  date: string;
  name: string | null;
  merchant_name: string | null;
  pending: boolean;
  payment_channel?: string;
  personal_finance_category?: { primary?: string } | null;
}

/**
 * Maps a Plaid transaction to SpendWise's event types.
 *
 * This is the single most important mapping in the integration, because only
 * `purchase` increases the user's spending. Plaid's sign convention is the
 * trap: a POSITIVE amount means money LEFT the account, and a negative amount
 * means money came in. Getting that backwards would turn every refund into
 * spending.
 */
function classify(txn: PlaidTransaction): string {
  const category = txn.personal_finance_category?.primary ?? '';
  const name = `${txn.merchant_name ?? ''} ${txn.name ?? ''}`.toLowerCase();

  // Money coming in.
  if (txn.amount < 0) {
    if (category === 'TRANSFER_IN' || /transfer|e-?transfer|interac/.test(name)) {
      return 'transfer';
    }
    return 'refund';
  }

  // Money going out.
  if (category === 'LOAN_PAYMENTS' || /payment.*(card|visa|mastercard)|thank you for your payment/.test(name)) {
    return 'payment';
  }
  if (category === 'TRANSFER_OUT' || /transfer|e-?transfer|interac/.test(name)) {
    return 'transfer';
  }
  return 'purchase';
}

/** Plaid's taxonomy mapped onto SpendWise's twelve categories. */
function mapCategory(primary?: string): string | null {
  switch (primary) {
    case 'FOOD_AND_DRINK': return 'dining';
    case 'GENERAL_MERCHANDISE': return 'shopping';
    case 'TRANSPORTATION': return 'transportation';
    case 'RENT_AND_UTILITIES': return 'utilities';
    case 'MEDICAL': return 'health';
    case 'ENTERTAINMENT': return 'entertainment';
    case 'HOME_IMPROVEMENT': return 'housing';
    case 'PERSONAL_CARE': return 'health';
    case 'TRAVEL': return 'transportation';
    default: return null;
  }
}

Deno.serve(endpoint(async (req, { user, admin }) => {
  const since = sinceDate((await body(req)).since);
  const { data: items, error } = await admin.from('linked_items')
    .select('id, access_token, institution_name, last_synced_at, provider')
    .eq('user_id', user.id);
  if (error) throw new ApiError('links_unavailable');
  const out: unknown[] = [], results: unknown[] = [];
  for (const item of items ?? []) {
    try {
      if (item.provider !== 'plaid') throw new ApiError('unsupported_provider', 400);
      const { transactions, accounts } = await pages(item.access_token, since, plaid);
      const normalized = transactions.filter((txn: PlaidTransaction) => !txn.pending).map((txn: PlaidTransaction) => ({
        provider_id: txn.transaction_id,
        amount_cents: Math.round(Math.abs(txn.amount) * 100),
        currency: txn.iso_currency_code ?? 'CAD', date: txn.date,
        event_type: classify(txn), merchant: txn.merchant_name ?? txn.name,
        account_id: txn.account_id, account_last4: accounts[txn.account_id] || null,
        category: mapCategory(txn.personal_finance_category?.primary), is_pending: txn.pending,
      }));
      const at = new Date().toISOString();
      const { error: updateError } = await admin.from('linked_items')
        .update({ last_synced_at: at, needs_reauth: false })
        .eq('id', item.id).eq('user_id', user.id);
      if (updateError) throw new ApiError('sync_state_failed');
      out.push(...normalized);
      results.push({ item_id: item.id, synced: normalized.length, error: null, retryable: false, last_synced_at: at });
    } catch (e) {
      const failure = e instanceof ApiError ? e : new ApiError('sync_failed');
      if (failure.code === 'reauth_required') await admin.from('linked_items')
        .update({ needs_reauth: true }).eq('id', item.id).eq('user_id', user.id);
      results.push({ item_id: item.id, synced: 0, error: failure.code, retryable: failure.retryable,
        last_synced_at: item.last_synced_at });
    }
  }
  return { transactions: out, results, partial_failure: results.some((r: any) => r.error !== null) };
}));
