import { test } from 'node:test';
import assert from 'node:assert/strict';
import { pages, sinceDate, ApiError } from '../functions/_shared/core.ts';

test('rejects invalid, future, wrong-type and excessive lookback dates', () => {
  const now = new Date('2026-10-15T12:00:00Z');
  for (const value of ['bad', '2026-12-01', '2020-01-01', '2026-02-31', null, 123]) {
    assert.throws(() => sinceDate(value, now), ApiError);
  }
  assert.equal(sinceDate('2026-10-01', now), '2026-10-01');
  assert.equal(sinceDate(undefined, now), '2026-07-17');
});
test('collects 601 transactions across all pages with correct offsets', async () => {
  const offsets: number[] = [];
  const result = await pages('secret', '2026-09-01', async (_path, params) => {
    const offset = (params.options as { offset: number }).offset;
    offsets.push(offset);
    return { total_transactions: 601, transactions: Array.from({length: offset === 0 ? 500 : 101}, (_, i) => ({transaction_id: `${offset + i}`})),
      accounts: [{account_id: 'account', mask: '1234'}] };
  });
  assert.deepEqual(offsets, [0, 500]);
  assert.equal(result.transactions.length, 601);
  assert.equal(result.accounts.account, '1234');
});
test('a failed later page rejects the whole item', async () => {
  let calls = 0;
  await assert.rejects(pages('secret', '2026-09-01', async () => {
    if (++calls === 2) throw new ApiError('provider_failed', 502, true);
    return { total_transactions: 600, transactions: Array(500).fill({}), accounts: [] };
  }), ApiError);
});
test('empty nonfinal and malformed pages cannot report success', async () => {
  for (const result of [{total_transactions: 600, transactions: []}, {total_transactions: -1, transactions: []}, {}]) {
    await assert.rejects(pages('secret', '2026-09-01', async () => result), ApiError);
  }
});
