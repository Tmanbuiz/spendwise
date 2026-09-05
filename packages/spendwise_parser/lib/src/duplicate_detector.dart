import 'models/parsed_transaction.dart';
import 'models/transaction_event_type.dart';

/// Why a candidate transaction was accepted or rejected.
enum DuplicateVerdict {
  /// New transaction; record it.
  accept,

  /// Same content fingerprint seen inside the time window — the bank sent the
  /// alert twice (push plus mirror, or a delivery retry).
  duplicateNotification,

  /// The parse produced nothing bookable, so there is nothing to deduplicate.
  notBookable,
}

class DuplicateDecision {
  const DuplicateDecision(this.verdict, {this.matchedFingerprint});

  final DuplicateVerdict verdict;
  final String? matchedFingerprint;

  bool get isDuplicate => verdict == DuplicateVerdict.duplicateNotification;
  bool get shouldStore => verdict == DuplicateVerdict.accept;
}

class _Seen {
  const _Seen(this.fingerprint, this.occurredAt);
  final String fingerprint;
  final DateTime occurredAt;
}

/// Suppresses repeat notifications for the same underlying transaction.
///
/// Identity comes from the fingerprint (bank, type, amount, merchant, card),
/// and *time* is applied here as a window rather than baked into the
/// fingerprint. That split matters: two copies of one alert can carry
/// different timestamps, while two genuinely separate coffees at the same shop
/// for the same amount are only distinguishable by how far apart they are.
class DuplicateDetector {
  DuplicateDetector({
    this.window = const Duration(minutes: 10),
    Iterable<ParsedTransaction> seed = const <ParsedTransaction>[],
  }) {
    for (final t in seed) {
      _record(t);
    }
  }

  /// How close together two identical events must be to count as one.
  ///
  /// Ten minutes is long enough to cover push/mirror delivery skew and short
  /// enough that a genuine repeat purchase later in the day still registers.
  final Duration window;

  final List<_Seen> _seen = <_Seen>[];

  /// Tests [candidate] and, when it is new, remembers it.
  DuplicateDecision evaluate(ParsedTransaction candidate) {
    if (!_isBookable(candidate)) {
      return const DuplicateDecision(DuplicateVerdict.notBookable);
    }

    _purgeOlderThan(candidate.occurredAt);

    for (final entry in _seen) {
      if (entry.fingerprint != candidate.fingerprint) continue;
      final gap = candidate.occurredAt.difference(entry.occurredAt).abs();
      if (gap <= window) {
        return DuplicateDecision(
          DuplicateVerdict.duplicateNotification,
          matchedFingerprint: entry.fingerprint,
        );
      }
    }

    _record(candidate);
    return const DuplicateDecision(DuplicateVerdict.accept);
  }

  /// Convenience wrapper for callers that only need a yes/no.
  bool isDuplicate(ParsedTransaction candidate) =>
      evaluate(candidate).isDuplicate;

  void clear() => _seen.clear();

  int get trackedCount => _seen.length;

  /// Declined events never moved money and unknown events were never
  /// understood, so neither is stored as a transaction and neither can be a
  /// duplicate of one.
  bool _isBookable(ParsedTransaction t) {
    if (t.eventType == TransactionEventType.unknown) return false;
    if (t.eventType == TransactionEventType.declined) return false;
    return t.amount != null && !t.amount!.isZero;
  }

  void _record(ParsedTransaction t) {
    _seen.add(_Seen(t.fingerprint, t.occurredAt));
  }

  /// Keeps the in-memory set bounded: anything that can no longer fall inside
  /// the window of a new event is dropped.
  void _purgeOlderThan(DateTime now) {
    final cutoff = now.subtract(window * 2);
    _seen.removeWhere((e) => e.occurredAt.isBefore(cutoff));
  }
}
