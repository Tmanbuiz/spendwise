-- Adds Education and Bank fees to the spend categories.
--
-- Both were landing in `other`, which is where anything unrecognised goes, so
-- neither could be seen at all:
--
--   * Tuition and registration arrive as a few large, irregular amounts. They
--     fit none of the existing categories, and folding them into Shopping
--     would misstate that one as well as hiding this.
--   * Service charges, overdraft and cash-advance fees are real money leaving
--     and do count as spending — but unlike groceries they are usually
--     avoidable, which is only actionable if they can be seen apart.
--
-- Appended rather than inserted in a tidy reading order: Postgres enum
-- ordering is physical, and BEFORE/AFTER rewrites how every existing row
-- sorts. Display order belongs to the client, which lists categories from the
-- Dart enum.
alter type spend_category add value if not exists 'education';
alter type spend_category add value if not exists 'bank_fees';
