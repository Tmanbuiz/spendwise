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

import { createClient } from 'jsr:@supabase/supabase-js@2';

const PLAID_HOSTS: Record<string, string> = {
  sandbox: 'https://sandbox.plaid.com',
  production: 'https://production.plaid.com',
};

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

Deno.serve(async (req: Request) => {
  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
    }

    // The user's own JWT is forwarded so RLS applies to every read below.
    // Using the service-role key here would bypass it.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return new Response(JSON.stringify({ error: 'unauthorized' }), { status: 401 });
    }

    const { data: items } = await supabase
      .from('linked_items')
      .select('id, access_token, institution_name');

    if (!items || items.length === 0) {
      return new Response(JSON.stringify({ transactions: [] }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const body = await req.json().catch(() => ({}));
    const since = body.since
      ? new Date(body.since)
      : new Date(Date.now() - 90 * 24 * 60 * 60 * 1000);

    const host = PLAID_HOSTS[Deno.env.get('PLAID_ENV') ?? 'sandbox'];
    const out: unknown[] = [];

    for (const item of items) {
      const response = await fetch(`${host}/transactions/get`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          client_id: Deno.env.get('PLAID_CLIENT_ID'),
          secret: Deno.env.get('PLAID_SECRET'),
          access_token: item.access_token,
          start_date: since.toISOString().slice(0, 10),
          end_date: new Date().toISOString().slice(0, 10),
        }),
      });

      if (!response.ok) {
        // One failing institution must not abort the whole sync.
        console.error(`Plaid sync failed for ${item.id}: ${response.status}`);
        continue;
      }

      const payload = await response.json();
      const accounts: Record<string, string> = {};
      for (const account of payload.accounts ?? []) {
        accounts[account.account_id] = account.mask ?? '';
      }

      for (const txn of (payload.transactions ?? []) as PlaidTransaction[]) {
        out.push({
          provider_id: txn.transaction_id,
          amount_cents: Math.round(Math.abs(txn.amount) * 100),
          currency: txn.iso_currency_code ?? 'CAD',
          date: txn.date,
          event_type: classify(txn),
          merchant: txn.merchant_name ?? txn.name,
          account_id: txn.account_id,
          account_last4: accounts[txn.account_id] || null,
          category: mapCategory(txn.personal_finance_category?.primary),
          is_pending: txn.pending,
        });
      }

      await supabase
        .from('linked_items')
        .update({ last_synced_at: new Date().toISOString() })
        .eq('id', item.id);
    }

    return new Response(JSON.stringify({ transactions: out }), {
      headers: { 'Content-Type': 'application/json' },
    });
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: 'sync_failed' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    });
  }
});
