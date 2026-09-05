# SpendWise

Automatic monthly spending tracking from bank and card payment notifications.
Android-first, Flutter, Supabase.

**Status: working MVP, running on real hardware.** Every screen is built, the
CIBC and Wealthsimple parsers are complete, statements import from CSV and PDF,
and 426 tests pass. The app has been installed and run on a physical Android
device: onboarding completes, notification access is granted, and CIBC's
package id is confirmed as `com.cibc.android.mobi`. A release APK builds and
sideloads.

Three ways in, all reconciled against each other so nothing is counted twice:
live notification capture, a downloaded statement, and — when it is configured
— a bank data aggregator.

The one step still unproven is end to end capture of a genuine CIBC purchase
alert on the device — see [Blockers](#blockers).

---

## What it does

Your bank already texts you every time you tap your card. SpendWise reads those
notifications, works out what they mean, and keeps a running total for the
month — with no bank login, no screen scraping, and no ability to move money.

The product rule everything else serves: **only purchases increase spending.**
Refunds, credit-card payments, transfers, declines and duplicate alerts are all
recognised and kept out of the total.

---

## Quick start

Requires the Flutter SDK (3.47+). If `flutter` is not on your PATH, use the
full path to `flutter.bat` (see [Toolchain notes](#toolchain-notes)).

```bash
cd spendwise/app && flutter pub get
```

```bash
cd spendwise/app && flutter analyze
```

```bash
cd spendwise/app && flutter test
```

```bash
cd spendwise/packages/spendwise_parser && dart test
```

Run it on a connected Android device or emulator:

```bash
cd spendwise/app && flutter run -d android
```

Run it in a browser (UI only — notification capture is Android-only):

```bash
cd spendwise/app && flutter run -d chrome
```

**The app runs with no configuration at all.** Without a Supabase project it
stores everything on the device and skips sign-in, so you can see the whole UI
immediately. Settings says plainly when data is local only.

---

## Configuration

```bash
cp spendwise/.env.example spendwise/app/.env
```

Then fill in `SUPABASE_URL` and `SUPABASE_ANON_KEY`. `.env` is git-ignored;
`.env.example` is the committed template. The Supabase **service-role key is
never used by the app** — it bypasses Row Level Security and belongs
server-side only.

| Variable | Purpose | Default |
| --- | --- | --- |
| `SUPABASE_URL` | Project URL. Empty = local-only mode | — |
| `SUPABASE_ANON_KEY` | Publishable key | — |
| `DEFAULT_CURRENCY` | Used when an alert omits a currency code | `CAD` |
| `DUPLICATE_WINDOW_MINUTES` | How close two identical alerts must be to count as one | `10` |
| `RAW_SAMPLE_RETENTION_DAYS` | Lifetime of a redacted unparsed sample | `30` |

### Supabase setup

1. Create a project at [supabase.com](https://supabase.com).
2. Run `supabase/migrations/0001_init.sql` in the SQL editor.
3. Copy the project URL and publishable key into `app/.env`.
4. Enable Email auth under Authentication → Providers.

The migration creates six tables, enables Row Level Security on all of them,
and adds a trigger that gives every new user a preferences row.

---

## Architecture

```
spendwise/
├── .env.example                   # config template; .env is git-ignored
├── supabase/
│   ├── migrations/                # schema + RLS policies
│   └── functions/aggregator-sync/ # holds the aggregator secrets, not the app
├── packages/spendwise_parser/     # pure Dart — no Flutter import anywhere
│   ├── lib/src/banks/             # cibc_*, wealthsimple_* parsers and rules
│   ├── lib/src/categorization/    # categoriser + Canadian merchant rules
│   ├── lib/src/import/            # statement readers (CSV, account PDF, card PDF)
│   ├── lib/src/util/              # amount, merchant, date, account, hashing
│   ├── lib/src/duplicate_detector.dart
│   └── test/                      # 299 tests
└── app/                           # the Flutter application
    ├── android/.../kotlin/        # NotificationListenerService + bridge
    ├── lib/core/                  # config, theme, router, formatters
    ├── lib/data/                  # models, repositories, monthly reporting
    │   └── aggregation/reconciler.dart  # keeps the three sources from doubling
    ├── lib/features/              # one folder per screen
    ├── lib/services/              # capture pipeline, statement import, aggregator
    ├── lib/state/providers.dart   # Riverpod
    └── test/                      # 127 tests
```

### Why the parser is a separate package

It has **no Flutter import anywhere**. That means its rules are unit-tested in
milliseconds with no emulator, and the planned iOS email importer can reuse the
engine unchanged — an email body wraps into the same `NotificationMessage`.

### The capture pipeline

```
Android notification
  → SpendWiseNotificationListenerService   (filters by watched package)
  → NotificationBridge                     (main thread, drops if no listener)
  → EventChannel → NotificationAccess
  → ParserRegistry → CibcParser            (classify, extract, fingerprint)
  → DuplicateDetector                      (10-minute window)
  → Categorizer                            (user rules beat built-ins)
  → TransactionRepository                  (Supabase or local)
```

The order is a product rule, not an implementation detail. Categorising before
deduplicating, or storing before deduplicating, would both double-count.

Filtering happens as early as possible: the Kotlin service checks the package
name before reading a notification's contents, so alerts from apps you did not
select are never read into memory at all.

---

## The CIBC parser

CIBC is documented in full because it is the parser everything else is
modelled on. Wealthsimple has its own parser and rules file built to the same
shape, and `ParserRegistry.standard()` routes an alert to whichever claims its
package — see [Adding another bank](#adding-another-bank).

### Event types

```
PURCHASE   money left the account for goods or services  →  counts as spending
REFUND     money came back from a merchant
PAYMENT    a payment toward a credit card or line of credit
TRANSFER   between own accounts, or an Interac e-Transfer
DECLINED   the card was refused; no money moved
UNKNOWN    from the bank, but not a transaction we understand
```

`TransactionEventType.countsAsSpending` is a whitelist, so any event type added
later defaults to *not* counting — the safe direction to fail. A purchase with
no recoverable amount also does not count, so a mangled alert cannot book $0.

### Why classification is an ordered chain

One notification routinely contains several keywords. *"A purchase of $200.00
at CANADIAN TIRE could not be completed"* is a purchase **and** a decline.
*"A bill payment of $142.08 to TORONTO HYDRO"* and *"a payment of $500.00 to
your CIBC Visa"* both contain "payment" — but only one is spending.

So the rules are a chain, most specific first, first match wins:

```
informational   → UNKNOWN    statement ready, fraud prompt, security code
declined        → DECLINED
refund          → REFUND
spendingPayment → PURCHASE   bill payment, pre-authorized debit
payment         → PAYMENT    destination is a card or line of credit
transfer        → TRANSFER
purchase        → PURCHASE   generic wording, catch-all last
```

`spendingPayment` sits above `payment` precisely so the word "payment" alone
cannot exclude a hydro bill from your spending.

One phrase is deliberately *not* informational: `"your available balance is"`.
It appears as a trailing clause on many genuine purchase alerts, so treating it
as informational would suppress real spending. A pure balance alert matches no
transaction tier and reaches `UNKNOWN` on its own.

### Extraction

Each field has its own extractor, so a partial match still yields a usable
transaction with its gaps recorded:

- **Amount** — two passes. The trusted pass requires a currency symbol or ISO
  code; a bare-number fallback requires exactly two decimals, because a bare
  integer is far more likely to be a card suffix. Matches surrounded by
  balance or limit wording are dropped, so the running balance quoted in the
  same sentence is never taken as the transaction amount.
- **Merchant** — anchored on `at` / `to` / `from` by event type, cut at a
  clause boundary. `and` and `in` are *not* boundaries, because real merchants
  contain them ("BED BATH AND BEYOND"). Times are rejected, so
  `"... at 7:02 p.m. at METRO"` still finds METRO.
- **Account** — last four digits and a product label. If anything
  card-number-shaped appears, the match is refused outright rather than four
  digits being sliced out of it.
- **Timestamp** — named-month, ISO and slash dates, 12- and 24-hour times. A
  month/day with no year resolves to the recent past, never the future.
  Falls back to delivery time, flagged inexact.
- **Currency** — `USD`, `US$`, `CAD`, `EUR`, `GBP`; defaults to CAD.

### Duplicate detection

Identity and time are kept separate on purpose:

- **Fingerprint** = bank + event type + currency + cents + normalised merchant
  + card last-4. Time is *not* in it, because two copies of one alert can carry
  different timestamps.
- **Time window** (10 minutes, configurable) is applied by `DuplicateDetector`.

That split catches a push/mirror pair straddling a minute boundary, while the
same coffee bought again in the afternoon still registers as a second
transaction. Merchant normalisation strips store numbers and processor
prefixes, so `SQ *BLUE DOOR CAFE #12` and `BLUE DOOR CAFE` fingerprint
identically. Declined and unknown events are never stored.

History is rebuilt from storage on launch, so a restart mid-stream does not let
an already-recorded alert through again.

### Categorisation

Twelve fixed categories. Two tiers, and the order between them is the point: a
rule you wrote always beats built-in knowledge. Within a tier the **longest
matching pattern wins**, so `AMAZON PRIME` beats `AMAZON` and `UBER EATS` beats
`UBER` with no hand-maintained priority column.

Built-in knowledge is weighted toward Canadian merchants — Loblaws, Tim
Hortons, Petro-Canada, Presto, Rogers, Shoppers Drug Mart and about 180 others.

---

## Importing a statement

Notification capture only sees what arrives from now on. Importing a statement
you download from online banking backfills the months before that, and settles
the amounts that a push alert only estimated.

Settings → **Import a statement** takes a `.csv`, `.pdf` or `.txt` file, shows
what it would do, and writes nothing until you confirm. The preview is not a
courtesy: an import is bulk, and one wrong column guess adds dozens of bad
rows at once.

### Three readers, because the sources differ in kind

| Reader | Input | How structure is recovered |
| --- | --- | --- |
| `StatementReader` | CSV | Detects the columns, with or without a header |
| `TextStatementReader` | Account statement PDF | Running balance says which way money moved |
| `CardStatementReader` | Credit card statement PDF | Section heading and sign say what a row means |

**CSV is the recommended format**, because its columns are real. A PDF stores
positioned glyphs and nothing else; the table has to be inferred back from
whatever the extractor emits, which is why the two PDF readers exist and why
the preview matters more for them.

Column detection is deliberately not hard-coded per bank. Every Canadian bank
exports something different — CIBC ships headerless rows with separate debit
and credit columns, others ship a header and one signed amount — and the
formats change without notice. The reader decides, then says what it decided
so you can correct it. When a single-amount file's sign convention is read
backwards, one tap flips it.

### Why a card statement needs its own reader

A credit-card statement is a structurally different document from a chequing
account statement, not a variation on one:

- **Every row carries two dates**, the transaction date and the posting date,
  where an account statement prints one date once per day. SpendWise records
  the transaction date — when you actually spent — which is also what a
  notification carries, so the two sources line up.
- **There is no running balance.** The account reader derives direction from a
  balance that rose or fell. A card statement offers no such arithmetic.
- **Rows are grouped under headings** that change what identical wording
  means. `PAYMENT THANK YOU/PAIEMENT MERCI` under *Your payments* is a card
  payment; `REGULAR PURCHASES` under *Your interest* is an interest charge.
  Neither reads as what it is from the words alone.

So the card reader takes its meaning from the section first, the sign second,
and the wording last — the reverse of a notification, where wording is all
there is. `CREDIT  TORONTO  ON  -90.75` is money coming back and nothing but
the minus sign says so.

A row is accepted only when the whole sequence appears in order: two plausible
dates, then a description, then an amount. Anything that interrupts that
discards the part-built row rather than completing it from what comes next.
Statements are dense with dates and amounts that are not transactions — a
credit limit, a minimum payment beside its due date, a section total — and a
reader that guesses at those does not merely miss a row, it **invents spending
that never happened**. An earlier version read a credit-limit box as a
$1,000.00 purchase; the strict sequence is what stops that.

Card-specific rules worth knowing:

- **Interest and fees count as spending.** They are real money leaving, and
  they are labelled `Interest — …` / `Fee — …` so they do not read as shops.
- **A cash advance does not.** It hands you your own credit as cash; counting
  it would double up against whatever that cash then buys. The **fee** for
  taking it does count.
- **CIBC's own spend categories are stripped** from the merchant name. They
  are the bank's classification, not part of the merchant, and leaving them in
  breaks matching against a notification-captured transaction.

### Nothing is ever counted twice

An imported row goes through `CrossSourceReconciler`, the same component the
aggregator path uses. A card tap fires a push alert in seconds; the statement
row for it turns up weeks later with a different date, a settled amount and a
cleaned-up merchant name. The reconciler matches on same card, same event
type, merchant agreeing loosely, date within a window and amount within a
tolerance, then **enriches the existing row rather than adding a second one**.
The preview says up front how many rows would be added, how many would merge,
and how many are already recorded.

---

## Privacy and security

- **Never stored, anywhere, in any form:** online banking passwords, PINs,
  CVVs, full card numbers. No column exists for them, and no code path can
  read one — `AccountExtractor` refuses the whole match when a card-number-
  shaped digit run is present. Tests assert this.
- **Raw notification text** is discarded the moment a complete parse is
  written. `toJson()` emits no raw field at all. Only when a parse is
  *incomplete* is a copy kept — redacted so every digit is masked, and only
  for 30 days. The database rejects a sample containing a digit, and a
  `purge_expired_samples()` function enforces the TTL server-side.
- **Row Level Security** on every table, with a separate policy per operation
  rather than one `FOR ALL`. The `WITH CHECK` on insert and update means a
  client cannot create a row for another user, nor update one of its own into
  belonging to someone else. `user_id` is never sent by the client — it
  defaults to `auth.uid()`.
- **Read-only by construction.** The app has no payment API and no bank
  credentials. It cannot move money.
- **Scoped capture.** Only packages belonging to banks you selected are read.

---

## Screens

Splash · Sign in / Sign up · Onboarding · Bank selection · Notification
permission · Dashboard · Transactions · Transaction detail/edit · Budgets ·
Categories & rules · Accounts · Statement import · Settings · Parser debug.

The **dashboard** shows the month's total, remaining budget, a category donut
with legend, recent activity, and the comparison with last month. Percent
change is hidden when last month was empty — "up 100% from nothing" would be
misleading.

The **parser debug screen** takes pasted notification text and shows the full
parse — type, amount, merchant, card, timestamp, confidence, fingerprint, what
could not be read, and the retention decision. Seven one-tap samples cover
every event type. Nothing is saved.

The **statement import screen** takes a downloaded CSV or PDF, shows the rows
it read, how many would be added, how many would merge into transactions
already captured, and how many are already recorded — then writes nothing
until you confirm.

**Bank support is stated honestly** on the selection screen: CIBC and
Wealthsimple read automatically; RBC, TD, Scotiabank, BMO and Other are
capture-only until their parsers land.

---

## Tests

**426 tests. All passing.** 299 in the parser package, 127 in the app.

| Suite | Tests | Covers |
| --- | ---: | --- |
| `cibc_parser_test.dart` | 82 | 38 realistic CIBC alerts, classification precedence, amount selection against balance noise, merchant/account/timestamp extraction, malformed input, fuzz |
| `categorizer_test.dart` | 40 | Built-in merchants, longest-match-wins, user overrides, invalid regex |
| `text_statement_reader_test.dart` | 38 | Account statement PDFs: both flattened layouts, direction from the balance, page furniture |
| `card_statement_reader_test.dart` | 32 | Card statement PDFs: section rules, sign rules, category stripping, and the summary-block figures that must never become rows |
| `statement_reader_test.dart` | 32 | CSV splitting, column detection, sign convention, debit/credit columns |
| `wealthsimple_real_alerts_test.dart` | 26 | Real alert wording, registry routing, no collision with CIBC |
| `cibc_real_alerts_test.dart` | 23 | Alerts captured from the device, verbatim |
| `reconciler_test.dart` | 23 | Match tolerances, merge vs insert, the double-counting failure |
| `duplicate_detector_test.dart` | 15 | Every identity field, time window, restart recovery |
| `raw_retention_test.dart` | 11 | Retention policy, redaction, no sensitive data |
| `ingest_service_test.dart` | 20 | End-to-end pipeline: what is and is not stored |
| `month_summary_test.dart` | 16 | Reporting, custom month start, budget progress |
| `screens_test.dart` | 24 | Every screen renders; filters, validation, empty states |
| `aggregator_client_test.dart` | 14 | Edge Function contract, token handling, failure paths |
| `capture_offline_test.dart` | 11 | Queueing and replay when storage is unreachable |
| `router_test.dart` | 11 | Every route reachable, guards, deep links |
| `widget_test.dart` | 8 | Money formatting, theme integrity |

The fixture corpus covers each event type, several card products, foreign
currency, thousands separators, processor-prefixed merchants, merchants
containing stop-words, and messages where the time precedes the merchant —
plus partial and malformed input: truncated mid-sentence, no whitespace, all
lower case, amount only, bank name only.

Statement fixtures are **synthetic**, modelled line by line on how a real
statement extracts but with invented merchants and figures, so no real
financial data lives in the repository.

---

## Blockers

1. **Notification capture is unverified end to end against a real alert.** The
   app runs on the user's device, notification access is granted, and the
   parser is tested against alerts captured verbatim from that phone — but the
   Kotlin listener → EventChannel → parser path has not yet been watched
   booking a genuine CIBC purchase as it happens. This is the last unproven
   link, and the parser debug screen exists partly to check it.
2. **No Supabase project exists yet.** The schema and RLS policies are written
   but have never been applied, so the SQL in `supabase/migrations/` is
   unexecuted and the app runs in local-only mode.
3. **No aggregator is configured.** `SupabaseAggregatorClient` and the
   `aggregator-sync` Edge Function are written and unit-tested against their
   contract, but no provider account exists, so that path has never run
   against a live API.

None of these are code defects — they are environment steps.

Resolved since the first draft: the Android SDK is installed
(`C:\Users\Atoye\dev\android-sdk`, command-line tools only), the app installs
and runs on a physical Samsung device, and
`flutter build apk --release --target-platform android-arm64` produces a
~21 MB sideloadable APK signed with the debug key. Play Protect warns on that
sideload because the app holds `BIND_NOTIFICATION_LISTENER_SERVICE` — the
warning is accurate, not a false positive.

---

## Adding another bank

1. Implement `BankNotificationParser` in `packages/spendwise_parser/lib/src/banks/`.
2. Add a rules file modelled on `cibc_rules.dart`.
3. Register it in `ParserRegistry.standard()`.
4. Add the package name to `Banks` in `app/lib/data/models/bank.dart` and set
   `supportLevel: BankSupport.full`.
5. Add a fixture list modelled on `cibc_samples.dart`.

No other file changes.

---

## Toolchain notes

Installed for this project on Windows. **None of it is on PATH.**

- **Flutter 3.47.2** at `C:\Users\Atoye\dev\flutter` (from Google's release
  archive — Flutter is not in winget). Call
  `C:\Users\Atoye\dev\flutter\bin\flutter.bat` or add `bin` to PATH.
- **Dart** — use the SDK Flutter bundles, at
  `C:\Users\Atoye\dev\flutter\bin\cache\dart-sdk\bin\dart.exe`. A separately
  winget-installed Google.DartSDK is on this machine but fails here with
  `Could not find bin\test.dart in package test`; the bundled one works.
- **Android SDK** at `C:\Users\Atoye\dev\android-sdk` — command-line tools
  rather than Android Studio, so setup is scriptable. `adb` is under
  `platform-tools\`.
- **JDK 17** via `winget install Microsoft.OpenJDK.17`.

The Flutter bash wrapper misbehaves under Git Bash on Windows; run
`flutter.bat` from PowerShell instead.

---

## Known limitations

- CIBC and Wealthsimple only. Other banks are unhandled by design, not
  oversight — they still capture, they just do not parse.
- A payment with no stated destination (*"Your payment of $500 was received"*)
  is classified `PAYMENT`, not `PURCHASE`. Deliberate: the cost of the
  conservative reading is an expense you add by hand, whereas guessing the
  other way would invent spending that never happened.
- Slash dates are read as M/D/Y unless the first field exceeds 12.
- Merchant extraction is anchor-based and cannot recover a merchant from text
  with no whitespace (`purchase$14.25atMCDONALDS`); the amount and type are
  still recovered and the merchant is left for you to fill in.
- Statement PDFs are read from CIBC's layouts. Another bank's PDF will import
  only as far as its shape happens to coincide; the preview is there so you
  see that before anything is written. CSV is the reliable path.
- A statement's spend categories from the bank are discarded rather than used
  as a categorisation hint. SpendWise categorises from the merchant name
  instead, so an imported row is categorised the same way a captured one is.
- Local-only mode does not sync or back up. It exists so the app is usable
  before Supabase is configured.

---

## Planned: iOS email import

iOS has no notification-listener API, so automatic capture there means reading
transaction emails instead. The architecture is ready for it and no Gmail
access is built yet:

- `TransactionSource.email` already exists in the model and the database enum.
- `NotificationMessage` is the only input shape the parsers accept; an email
  body wraps into it with no parser changes.
- The parser package has no Flutter dependency, so it could equally run in a
  server-side function that processes mail.
