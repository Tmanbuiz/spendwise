# SpendWise 1.1 — spending clarity

The native Android app now has a navy and teal visual system, a redesigned home dashboard, and an Insights tab alongside Home, Activity, Budgets, and Settings. Both light and dark modes follow the device theme. A new adaptive launcher icon replaces the Flutter starter icon.

## Insights and budgets

- Monthly total and budget remaining, with a daily allowance that includes today and never goes below zero.
- Matching-period comparisons: the first N days of each period, clipped to the shorter period when necessary. The UI explicitly notes that today can be incomplete.
- Tappable daily spending chart with exact amounts and accessible day labels.
- Six-period spending history, category breakdown, top merchants, and average purchase size.
- A labelled linear period-end estimate after day seven when there is recorded spending. This is a spending estimate, not a bank balance or guaranteed prediction.
- Category budget statuses, allocation totals, and an explanation when category limits exceed the overall limit.
- Optional budget suggestions based on prior-period category spending, rounded up to the next $10. Selecting a suggestion opens the editable form; nothing is saved automatically.
- Budget editing preserves cents, rejects malformed amounts, prevents duplicate limits, and reports save/delete failures.

## Reporting correctness

Period navigation starts from the actual pay-cycle start, avoiding month-end overflow (for example, March 31 navigating back to February). Date counts use calendar days rather than elapsed hours, so daylight saving time does not change allowances. Reporting filters by the selected currency instead of adding different currencies together. Purchases recorded after the current moment are excluded from current insights. The reporting clock refreshes with transactions and periodically while the app remains open.

Budget limits are recurring settings, not historical snapshots: editing a limit changes the budget comparison shown for past periods. The UI explains this. The dashboard's recent activity now follows the selected period.

## Preservation

The application ID remains `com.spendwise.spendwise`. No storage keys, schemas, transaction records, notification listener code, parser rules, or cloud configuration were migrated. The release build uses the existing debug signing configuration for personal sideloading. An update must have the same signing certificate as the installed app; never uninstall the existing app to work around a mismatch, because local data would be lost.

The supplied APK runs in local mode. Supabase and aggregator services remain optional and are not provisioned by this redesign.

## Validation

Verified for this revision: 147 app tests and 299 parser tests pass. Phone-size previews were inspected in light and dark mode, and the compact layout was checked with enlarged text. The installed app's signing certificate matches the release signing identity used here.

Run `flutter analyze` and `flutter test` in `app`, then `dart test` in `packages/spendwise_parser`. The new calculation tests cover matching periods, February and pay-cycle navigation, DST-independent day counts, currency isolation, exclusions, forecasts, allowance arithmetic, and merchant grouping. UI tests exercise real tab navigation, chart selection, precise budget editing, light/dark rendering, and a compact phone with enlarged text.

Preview images are rendered from the actual Flutter widgets using fictional test data, not the user's financial records. To regenerate them, set `SPENDWISE_PREVIEW_DIR` and optionally `SPENDWISE_PREVIEW_FONT`, then run `flutter test test/redesign_ui_test.dart`.
