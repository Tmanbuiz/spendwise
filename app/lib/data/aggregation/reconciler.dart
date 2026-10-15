import 'package:spendwise_parser/spendwise_parser.dart';

import '../models/app_transaction.dart';
import 'aggregator_models.dart';

/// What to do with one incoming aggregator transaction.
enum ReconcileAction {
  /// Not seen before. Insert it.
  insert,

  /// The same transaction already arrived as a bank notification. Enrich the
  /// existing row instead of adding a second one.
  mergeIntoExisting,

  /// Already imported from this aggregator on an earlier sync. Update in place.
  updateExisting,

  /// Recognised but deliberately not stored â a decline, or an event type the
  /// app does not record.
  skip,
}

class ReconcileResult {
  const ReconcileResult(this.action, {this.existing, this.merged});

  final ReconcileAction action;

  /// The row this matched, when the action is a merge or an update.
  final AppTransaction? existing;

  /// The row to write. Null when [action] is [ReconcileAction.skip].
  final AppTransaction? merged;

  bool get writes => merged != null;
}

/// Decides whether an aggregator transaction is new, or is one SpendWise
/// already recorded from a bank notification.
///
/// This exists because the two sources overlap completely. A card tap fires a
/// push alert within seconds; the same purchase arrives from the aggregator a
/// day or two later. Without reconciliation, enabling an aggregator would
/// silently double every total the user has â the single worst failure this
/// app could have.
///
/// Matching cannot be exact, because the two sources genuinely disagree:
///
///   * **Amount** â a restaurant notification says $40.00 when the card is
///     tapped; the posted amount is $48.00 once the tip is added. Foreign
///     purchases drift with the exchange rate.
///   * **Merchant** â a notification carries the terminal string
///     (`SQ *BLUE DOOR CAFE #12`); aggregators return a cleaned name
///     (`Blue Door Cafe`).
///   * **Date** â the notification is the moment of purchase; the aggregator
///     date is when it posted, up to several days later.
///
/// So matching is: same card, same event type, merchant agreeing loosely,
/// date within a window, amount within a tolerance.
class CrossSourceReconciler {
  const CrossSourceReconciler({
    this.dateWindow = const Duration(days: 4),
    this.amountTolerance = 0.30,
    this.absoluteToleranceCents = 2500,
  });

  /// How long after a notification a posted transaction may still be the same
  /// purchase. Four days covers a weekend plus a bank holiday.
  final Duration dateWindow;

  /// Fractional amount drift allowed, to absorb tips and FX. 0.30 covers a
  /// 25% tip with room to spare.
  final double amountTolerance;

  /// Upper bound on that drift in absolute terms, so a large purchase does not
  /// get an implausibly wide window â 30% of $3,000 would otherwise match
  /// almost anything.
  final int absoluteToleranceCents;

  /// Reconciles [incoming] against [existing] rows.
  ReconcileResult reconcile(
    AggregatorTransaction incoming,
    List<AppTransaction> existing, {
    required String Function() idGenerator,
    Categorizer? categorizer,
    TransactionSource source = TransactionSource.aggregator,
  }) {
    // Declines never moved money, so there is nothing to record and nothing
    // to reconcile against.
    if (incoming.eventType == TransactionEventType.declined ||
        incoming.eventType == TransactionEventType.unknown) {
      return const ReconcileResult(ReconcileAction.skip);
    }

    // An earlier sync of the same aggregator record. Identity is exact here,
    // so this is checked before any fuzzy matching.
    final previouslyImported = existing
        .where((t) => t.fingerprint == _providerFingerprint(incoming))
        .firstOrNull;
    if (previouslyImported != null) {
      return ReconcileResult(
        ReconcileAction.updateExisting,
        existing: previouslyImported,
        merged: _apply(incoming, previouslyImported, categorizer),
      );
    }

    final match = _findNotificationMatch(incoming, existing);
    if (match != null) {
      return ReconcileResult(
        ReconcileAction.mergeIntoExisting,
        existing: match,
        merged: _apply(incoming, match, categorizer),
      );
    }

    return ReconcileResult(
      ReconcileAction.insert,
      merged: _newTransaction(incoming, idGenerator(), categorizer, source).copyWith(
        needsReview: existing.any((t) => t.source == TransactionSource.notification &&
          t.eventType == incoming.eventType && t.currency == incoming.currency &&
          incoming.date.difference(t.occurredAt).abs() <= dateWindow &&
          _amountsAgree(incoming.amountCents, t.amountCents)),
      ),
    );
  }

  /// The best notification-sourced candidate, or null.
  ///
  /// Only notification rows are considered: a manually entered transaction is
  /// the user's deliberate record and is never silently absorbed.
  AppTransaction? _findNotificationMatch(
    AggregatorTransaction incoming,
    List<AppTransaction> existing,
  ) {
    AppTransaction? best;
    var bestScore = 0.0;
    var plausible = 0;

    for (final candidate in existing) {
      if (candidate.source != TransactionSource.notification) continue;
      if (candidate.eventType != incoming.eventType) continue;
      if (candidate.currency != incoming.currency) continue;

      final score = _score(incoming, candidate);
      if (score >= 0.75) plausible++;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    // A partial match is worse than none: wrongly merging hides a real
    // transaction, which is harder for the user to notice than a duplicate.
    return bestScore >= 0.75 && plausible == 1 ? best : null;
  }

  /// 0..1 confidence that these are the same purchase.
  double _score(AggregatorTransaction incoming, AppTransaction candidate) {
    // A fuzzy merge requires positive card identity; missing digits are reviewed.
    if (incoming.accountLast4 == null || incoming.accountLast4!.isEmpty ||
        candidate.accountLast4 == null || incoming.accountLast4 != candidate.accountLast4) return 0;
    if (incoming.accountId != null && candidate.accountId != null && incoming.accountId != candidate.accountId) return 0;
    // The date gate is absolute: the posted date can trail the purchase but
    // never precede it by more than a day of clock skew.
    final drift = incoming.date.difference(candidate.occurredAt);
    if (drift > dateWindow || drift < const Duration(days: -1)) return 0;

    if (!_amountsAgree(incoming.amountCents, candidate.amountCents)) return 0;

    final affinity = _merchantAffinity(
      incoming.merchantNormalized,
      candidate.merchantNormalized,
    );

    // Merchant is the strongest identity signal, so a *known* disagreement is
    // a veto rather than a deduction. Two $45.67 purchases on the same card on
    // the same day at different shops are entirely ordinary, and merging them
    // would delete one â a worse failure than showing a duplicate.
    final bothMerchantsKnown = incoming.merchantNormalized != null &&
        candidate.merchantNormalized != null;
    if (bothMerchantsKnown && affinity < _merchantVetoFloor) return 0;

    var score = 0.4; // same type, currency and plausible date

    if (_cardsAgree(incoming.accountLast4, candidate.accountLast4)) {
      score += 0.25;
    }

    final exactAmount = incoming.amountCents == candidate.amountCents;
    score += exactAmount ? 0.2 : 0.05;

    score += affinity * 0.25;

    return score.clamp(0.0, 1.0);
  }

  /// Below this, two known merchant names are treated as different businesses.
  /// One shared significant token clears it; none does not.
  static const double _merchantVetoFloor = 0.34;

  bool _amountsAgree(int incoming, int existing) {
    if (incoming == existing) return true;
    // Only an increase is expected: tips and FX push the posted amount up, so
    // a posted amount well below the alert is a different purchase.
    if (incoming < existing) return false;
    final allowed = (existing * amountTolerance)
        .round()
        .clamp(0, absoluteToleranceCents);
    return incoming - existing <= allowed;
  }

  /// Unknown card digits are neutral, not disqualifying â plenty of alerts
  /// omit them.
  bool _cardsAgree(String? a, String? b) {
    if (a == null || b == null) return false;
    return a == b;
  }

  /// 0..1 similarity between two normalised merchant names.
  ///
  /// Deliberately crude: token overlap and prefix containment, not an edit
  /// distance. `SQ *BLUE DOOR CAFE #12` normalises to `BLUE DOOR CAFE`, which
  /// already shares every token with the aggregator's `Blue Door Cafe`.
  double _merchantAffinity(String? a, String? b) {
    if (a == null || b == null) return 0.5; // unknown, so neither helps nor hurts
    if (a == b) return 1.0;
    if (a.contains(b) || b.contains(a)) return 0.9;

    final tokensA = a.split(' ').where((t) => t.length > 2).toSet();
    final tokensB = b.split(' ').where((t) => t.length > 2).toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.3;

    final shared = tokensA.intersection(tokensB).length;
    if (shared == 0) return 0.0;
    return shared / (tokensA.length > tokensB.length
        ? tokensA.length
        : tokensB.length);
  }

  /// Folds aggregator data into an existing row.
  ///
  /// The aggregator wins on amount, date and merchant, because a posted
  /// transaction is authoritative over an alert. The user always wins on
  /// category: a correction they made is never overwritten.
  AppTransaction _apply(
    AggregatorTransaction incoming,
    AppTransaction existing,
    Categorizer? categorizer,
  ) {
    final merchant = incoming.merchant ?? existing.merchant;
    final category = existing.categoryWasSetByUser
        ? existing.category
        : _categoryFor(incoming, merchant, categorizer);

    return existing.copyWith(
      amountCents: incoming.amountCents,
      occurredAt: incoming.date,
      merchant: merchant,
      merchantNormalized: MerchantExtractor.normalize(merchant),
      category: category,
      accountLast4: incoming.accountLast4 ?? existing.accountLast4,
      fingerprint: _providerFingerprint(incoming),
      // A posted transaction resolves whatever the alert could not read —
      // including which way the money went, which an alert rarely says.
      direction: incoming.recordedDirection,
      needsReview: false,
    );
  }

  AppTransaction _newTransaction(
    AggregatorTransaction incoming,
    String id,
    Categorizer? categorizer,
    TransactionSource source,
  ) {
    return AppTransaction(
      id: id,
      eventType: incoming.eventType,
      amountCents: incoming.amountCents,
      currency: incoming.currency,
      occurredAt: incoming.date,
      category: _categoryFor(incoming, incoming.merchant, categorizer),
      source: source,
      merchant: incoming.merchant,
      merchantNormalized: incoming.merchantNormalized,
      accountId: incoming.accountId,
      accountLast4: incoming.accountLast4,
      fingerprint: _providerFingerprint(incoming),
      recordedDirection: incoming.recordedDirection,
      needsReview: incoming.accountLast4 == null,
    );
  }

  /// SpendWise's own rules first, the aggregator's category only as a
  /// fallback â the user's rules must beat a third party's guess.
  SpendCategory _categoryFor(
    AggregatorTransaction incoming,
    String? merchant,
    Categorizer? categorizer,
  ) {
    final ours = categorizer?.categorize(
      MerchantExtractor.normalize(merchant),
    );
    if (ours != null && ours.isConfident) return ours.category;
    return incoming.category ?? ours?.category ?? SpendCategory.other;
  }

  /// Aggregator rows are identified by the provider's own id, which is stable
  /// across syncs â no fuzzy hashing needed once a row has one.
  static String _providerFingerprint(AggregatorTransaction incoming) =>
      'agg:${incoming.providerId}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
