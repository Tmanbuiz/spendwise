import 'package:spendwise_parser/spendwise_parser.dart';

import '../data/models/app_transaction.dart';
import '../data/models/bank.dart';

/// What happened to one captured notification.
enum IngestStatus {
  /// A new transaction was written.
  stored,

  /// The bank sent the same event twice.
  duplicate,

  /// Understood, but not something we record: a decline, or an
  /// informational message.
  notRecorded,

  /// From a bank the user did not select, so it was never examined.
  bankNotSelected,

  /// From a selected bank with no parser yet. Kept as an unparsed sample the
  /// user can turn into a transaction by hand.
  unsupportedBank,
}

class IngestResult {
  const IngestResult(this.status, {this.transaction, this.parsed, this.note});

  /// Why this outcome happened, in one line, for the diagnostics screen.
  ///
  /// Capture runs with no UI attached, so when a notification does not become
  /// a transaction there is otherwise nothing to inspect — the counters say
  /// something arrived and the dashboard says nothing was recorded, with no
  /// way to see which step discarded it.
  final String? note;

  final IngestStatus status;

  /// Present when [status] is [IngestStatus.stored].
  final AppTransaction? transaction;

  /// The raw parse, for the debug screen.
  final ParsedTransaction? parsed;

  bool get wasStored => status == IngestStatus.stored;
}

/// Where ingested transactions go. Abstracted so the pipeline can be tested
/// without Supabase.
abstract interface class TransactionSink {
  Future<void> save(AppTransaction transaction);

  /// Recent transactions, used to seed duplicate detection after a restart.
  Future<List<AppTransaction>> recent({required Duration window});

  /// Whether a transaction with [fingerprint] is already stored near [at].
  ///
  /// Storage is the authority on what has already been recorded. The
  /// in-memory detector only knows what this process has seen, which is not
  /// enough: re-reading the notification shade replays alerts that may be days
  /// old, and any provider rebuild hands the pipeline a fresh, empty detector.
  /// Both of those silently duplicated transactions until this check existed.
  Future<bool> existsNear(String fingerprint, DateTime at, Duration window);
}

/// Generates ids for new transactions. Injected so tests are deterministic.
typedef IdGenerator = String Function();

/// The capture pipeline: parse, deduplicate, categorise, store.
///
/// Deliberately one class with one entry point, because the ordering of these
/// four steps is a product rule, not an implementation detail. Categorising
/// before deduplicating, or storing before deduplicating, would both produce
/// double-counted spending.
class IngestService {
  IngestService({
    required this.sink,
    required this.idGenerator,
    ParserRegistry? registry,
    Categorizer? categorizer,
    Duration duplicateWindow = const Duration(minutes: 10),
  })  : _registry = registry ?? ParserRegistry.standard(),
        _categorizer = categorizer ?? Categorizer(),
        _duplicateWindow = duplicateWindow,
        _detector = DuplicateDetector(window: duplicateWindow);

  final Duration _duplicateWindow;

  final TransactionSink sink;
  final IdGenerator idGenerator;
  final ParserRegistry _registry;
  Categorizer _categorizer;
  final DuplicateDetector _detector;

  /// Replaces the categoriser, e.g. after the user edits their merchant rules.
  void updateRules(List<MerchantRule> userRules) {
    _categorizer = _categorizer.withUserRules(userRules);
  }

  /// Rebuilds duplicate history from storage, so a restart mid-stream does not
  /// let an already-recorded alert through a second time.
  Future<void> warmUp({Duration window = const Duration(hours: 2)}) async {
    final recent = await sink.recent(window: window);
    _detector.clear();
    for (final transaction in recent) {
      final fingerprint = transaction.fingerprint;
      if (fingerprint == null) continue;
      _detector.evaluate(
        ParsedTransaction(
          bankId: transaction.bankId ?? 'unknown',
          eventType: transaction.eventType,
          amount: Money(transaction.amountCents, transaction.currency),
          merchantNormalized: transaction.merchantNormalized,
          accountLast4: transaction.accountLast4,
          occurredAt: transaction.occurredAt,
          occurredAtIsExact: true,
          fingerprint: fingerprint,
          rawRetention: RawRetention.discard,
        ),
      );
    }
  }

  /// Runs one captured notification through the pipeline.
  Future<void> _tail = Future<void>.value();

  Future<IngestResult> ingest(NotificationMessage message, {required Set<String> selectedBankIds}) {
    final result = _tail.then((_) => _ingest(message, selectedBankIds: selectedBankIds));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<IngestResult> _ingest(
    NotificationMessage message, {
    required Set<String> selectedBankIds,
  }) async {
    final bank = Banks.byPackage(message.packageName);

    // Notifications from apps the user did not select never get examined.
    // Narrowing here rather than later means unrelated apps' text is not even
    // read, let alone stored.
    if (bank == null) {
      return IngestResult(
        IngestStatus.bankNotSelected,
        note: 'Unknown package ${message.packageName}',
      );
    }
    if (!selectedBankIds.contains(bank.id)) {
      return IngestResult(
        IngestStatus.bankNotSelected,
        note: '${bank.shortName} is not in your selected banks '
            '(${selectedBankIds.join(", ")})',
      );
    }

    final parsed = _registry.parse(message);
    if (parsed == null) {
      return IngestResult(
        IngestStatus.unsupportedBank,
        note: 'No parser for ${bank.shortName}',
      );
    }

    // Declines and informational messages are understood but not recorded:
    // no money moved, so nothing belongs in the ledger.
    if (!parsed.isTransaction) {
      return IngestResult(
        IngestStatus.notRecorded,
        parsed: parsed,
        note: 'Not read as a transaction',
      );
    }
    if (parsed.eventType == TransactionEventType.declined) {
      return IngestResult(
        IngestStatus.notRecorded,
        parsed: parsed,
        note: 'Declined — no money moved',
      );
    }
    if (parsed.amount == null) {
      return IngestResult(
        IngestStatus.notRecorded,
        parsed: parsed,
        note: 'No amount could be read',
      );
    }

    // Storage first, memory second. Storage knows about every earlier run of
    // the app; the detector only knows about this one.
    final alreadyStored = await sink.existsNear(
      parsed.fingerprint,
      parsed.occurredAt,
      _duplicateWindow,
    );
    if (alreadyStored) {
      return IngestResult(
        IngestStatus.duplicate,
        parsed: parsed,
        note: 'Already stored — same alert read again',
      );
    }

    if (_detector.evaluate(parsed).isDuplicate) {
      return IngestResult(
        IngestStatus.duplicate,
        parsed: parsed,
        note: 'Already recorded within the duplicate window',
      );
    }

    final transaction = toAppTransaction(parsed, bankId: bank.id);
    try { await sink.save(transaction); } on Object {
      // evaluate() reserves in memory before saving; a failed write must remain retryable.
      _detector.clear();
      rethrow;
    }
    return IngestResult(
      IngestStatus.stored,
      transaction: transaction,
      parsed: parsed,
      note: '${transaction.displayMerchant} · '
          '${(transaction.amountCents / 100).toStringAsFixed(2)}',
    );
  }

  /// Converts a parse into a storable transaction, applying categorisation.
  ///
  /// Public so the debug screen can show exactly what would be stored without
  /// storing it.
  AppTransaction toAppTransaction(
    ParsedTransaction parsed, {
    required String bankId,
  }) {
    final amount = parsed.amount;
    return AppTransaction(
      id: idGenerator(),
      eventType: parsed.eventType,
      amountCents: amount?.cents ?? 0,
      currency: amount?.currency ?? 'CAD',
      occurredAt: parsed.occurredAt,
      category: _categorizer.categoryFor(parsed.merchantNormalized),
      source: TransactionSource.notification,
      merchant: parsed.merchantRaw,
      merchantNormalized: parsed.merchantNormalized,
      accountLabel: parsed.accountLabel,
      accountLast4: parsed.accountLast4,
      bankId: bankId,
      fingerprint: parsed.fingerprint,
      // An incomplete parse is surfaced for confirmation rather than silently
      // trusted, so the user can fix it before it skews a budget.
      needsReview: !parsed.isComplete,
    );
  }
}
