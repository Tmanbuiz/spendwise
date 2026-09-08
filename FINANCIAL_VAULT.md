# SpendWise Financial Vault & Private Analysis

This feature extends SpendWise from a transaction tracker into a persistent financial record system without replacing the existing parser, repository, Riverpod, or reporting architecture.

## Financial Vault

The vault keeps the source files behind imported financial history so a user does not need to repeatedly find or upload the same statement.

### Local mode

When Supabase is not configured, source documents are copied into the application's private documents directory under `financial_documents/`. Metadata is kept through the local repository.

This is device-local storage. It is not a cloud backup and should not be described as synced.

### Synced mode

When Supabase is configured and the user is signed in:

- metadata lives in `public.financial_documents`;
- source bytes live in the private `financial-documents` Storage bucket;
- object paths are `<auth.uid()>/<document-id>/<safe-file-name>`;
- table RLS and Storage policies restrict reads and writes to that authenticated user;
- no public URL is generated.

Apply `supabase/migrations/0003_financial_vault.sql` before enabling this feature against a hosted Supabase project.

### Statement import

A confirmed CSV/PDF/TXT statement import still writes reconciled structured transactions first. Archiving the source file happens afterward and is best-effort: a temporary Storage problem must not undo a correct transaction import.

A statement is considered already archived when filename, byte size, and parsed date coverage match an existing vault document.

## Financial Memory

Financial Memory rules live above the ordinary merchant category rules.

A category rule answers:

> Which expense category is this merchant?

A Financial Memory rule answers:

> Should this transaction be treated as spending, income, investing/savings, an internal household transfer, or ignored in analysis?

Supported classifications:

- Expense
- Investment / savings
- Income
- Internal household transfer
- Ignore in analysis

Supported matching modes:

- Contains
- Exact match
- Starts with
- Regular expression

When several enabled rules match, the longest matching pattern wins. This allows a broad household rule to be overridden by a more specific one.

Examples:

- `Wealthsimple` → Investment / savings
- `CIBC Securities` → Investment / savings
- `HARMONY FAMILY` → Income
- `BEYOND BEHAVIOURAL` → Income
- `Spouse transfer` → Internal household transfer

These are examples only. SpendWise never installs them silently because the meaning of a merchant or transfer is household-specific.

## Ask SpendWise

`Ask SpendWise` is currently a deterministic private query engine over the user's structured transactions and Financial Memory rules. It is intentionally not an external LLM integration.

That means financial data is not sent to a third-party AI provider in order to answer questions.

Supported question families include:

- spending total for this month / last month / a named month / year;
- month ranges such as January through August;
- grocery and other category totals;
- known merchant totals;
- top merchants;
- top categories;
- highest-spending month;
- month-to-month comparisons;
- transactions captured by Investment / savings rules;
- transactions captured by Income rules;
- mortgage-readiness questions, with an explicit refusal to infer an approval amount from spending alone.

The query engine keeps currencies isolated. It applies Financial Memory before deciding which transactions count as spending.

## Why structured transactions come first

PDFs are source evidence, not the analytical database. SpendWise parses and reconciles a statement once, stores the resulting transactions, and then answers questions from structured records. This is faster, easier to test, and more reliable than repeatedly extracting every PDF for every question.

The original document remains available in Financial Vault for audit/review.

## Validation

The feature adds focused tests for:

- Financial Vault metadata serialization;
- Financial Memory matching and serialization;
- rule-aware private financial questions.

The repository also gains `.github/workflows/quality.yml`, which runs:

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. parser `dart pub get`
5. parser `dart test`

The feature branch should remain a draft PR until those checks are green.
