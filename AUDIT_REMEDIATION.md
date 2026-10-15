# Audit remediation — 15 October 2026

Changes are on `fix/audit-remediation-2026-10-15` (PR #2). They are **not a verified production release**.

## Implemented

- F01: JWT verification, owner-scoped privileged credential queries, removal of client credential writes, metadata-only column grants and RLS. Added link-token, exchange and unlink functions.
- F05: bounded date validation, all `/transactions/get` pages, transient retries, per-item failure results, successful timestamps only after complete retrieval. Only posted transactions are delivered; pending alerts remain provisional until posting. Client reports partial sync failures rather than claiming success.
- F02: AES-256-GCM encrypted SQLite payloads; key in platform secure storage, with iOS device-only accessibility. Legacy preferences migrate transactionally and are read back before plaintext removal. Corrupt data fails closed. Bills migrate too. Android application backup disabled.
- F03/F04: insert-only default, explicit overwrite toggle and confirmation, conflict counts, prevalidated account references, and one local SQLite transaction including bills and optional preferences. Synced restore is disabled until a transactional server implementation exists.
- F06: encrypted durable Android queue, IDs and explicit acknowledgments after ingestion, serial ingestion, failure retries/dead-letter counts, manual retry, and queue-overflow warnings. Failed ledger writes release the in-memory duplicate reservation.
- F07: mismatched/missing card identity and missing merchant identity cannot trigger fuzzy merges. Multiple plausible candidates stay separate and are marked for review; exact provider identities still update in place.
- F08: backend date/pagination tests, encrypted-storage/migration/rollback tests, conservative-reconciliation tests, RLS and vault-owner SQL tests, iOS build and secret scanning. Exception text is removed from central diagnostics.
- Fixed parser package path from `../packages` to `../../packages`.

## Deployment sequence

1. Run Flutter analysis/tests, parser tests, release Android build, and unsigned iOS build. `flutter pub get` must regenerate the app lockfile for the new dependencies.
2. Run ephemeral Supabase migration/RLS tests. Apply migration `0007_link_credential_security.sql` to the intended project only after those pass.
3. Configure `PLAID_CLIENT_ID`, `PLAID_SECRET`, `PLAID_ENV` in Supabase secrets. Service-role credentials must remain server-only. For Link, configure the registered Android package and/or redirect URI as required by the platform.
4. Deploy `aggregator-link-token`, `aggregator-exchange-token`, `aggregator-sync`, and `aggregator-unlink` together.
5. Sandbox-test two users: each may see/sync/unlink only their own bank connections; expired/invalid JWTs return 401; no client query can select access tokens or mutate credentials.
6. Upgrade an installation with representative legacy records. Compare IDs, counts and totals, interrupt migration/restore, tamper with ciphertext, and test notification processing through process death and reboot.
7. On device, test access before first unlock, secure-storage behavior, genuine redacted bank alerts, queue overflow and failed-alert retries. Validate statement totals before release.

## Remaining limits / release gates

- Four backend tests pass locally. Flutter/Dart, Android/iOS SDKs and Supabase/Docker are unavailable in the editing workspace.
- GitHub run `38756996221` failed all jobs before any step executed (runner ID 0); no CI validation or APK was produced. The API supplied no job logs or underlying cause. Resolve runner/account availability and rerun; do not interpret those failures as passing or failing code tests.
- SQLite currently indexes encrypted collections, not individual transaction fields. A per-record indexed layout is still needed for large histories.
- Existing vault files upgrade to encryption when read. Unread legacy documents still need an eager upgrade pass before a production release. New documents are encrypted immediately.
- Exported JSON backups remain readable and carry a privacy notice. Passphrase-encrypted exports, conflict-by-conflict merge review, and a full destructive restore mode are not implemented.
- `/transactions/get` does not provide durable removal events. Modified records update by stable provider ID; provider removals and pending ID replacement need a cursor-based sync design before claiming complete bank-ledger mirroring.
- Partial bank failures currently abort client ingestion of that response so the user must retry; successful-bank results are not independently committed.
- Ingestion is serialized within a service and local mutations are transactional. Cross-device notification uniqueness in Supabase still needs a database-side ingest operation.
- Device-level crash/reboot tests, labeled false-merge thresholds, dependency-vulnerability auditing, and SHA-pinning of third-party actions remain release work.
- No live Supabase project, credentials, bank links or customer data were modified.
