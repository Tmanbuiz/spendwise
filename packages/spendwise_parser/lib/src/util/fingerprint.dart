import '../models/money.dart';
import '../models/transaction_event_type.dart';

/// Builds the content identity of a transaction, used for duplicate detection.
///
/// Time is deliberately NOT part of the fingerprint. Banks frequently send the
/// same event twice (push + SMS-style mirror, or a retry) seconds or minutes
/// apart, and the two copies can straddle a minute boundary or carry different
/// timestamps. Identity is "what happened"; "when" is handled by the time
/// window in the duplicate detector.
abstract final class TransactionFingerprint {
  static String build({
    required String bankId,
    required TransactionEventType eventType,
    Money? amount,
    String? merchantNormalized,
    String? accountLast4,
  }) {
    final parts = <String>[
      bankId.toLowerCase(),
      eventType.wireName,
      amount?.currency ?? '-',
      amount?.cents.toString() ?? '-',
      merchantNormalized ?? '-',
      accountLast4 ?? '-',
    ];
    return _hash64(parts.join('|'));
  }

  /// FNV-1a, run forwards and backwards to fill 64 bits of hex.
  ///
  /// Hand-rolled rather than pulled from `package:crypto` so the parser stays
  /// dependency-free, and masked to 32 bits per half so the value is identical
  /// on native and on web (where Dart ints are doubles).
  static String _hash64(String input) {
    final units = input.codeUnits;
    final forward = _fnv1a(units);
    final backward = _fnv1a(units.reversed.toList(growable: false));
    return forward.toRadixString(16).padLeft(8, '0') +
        backward.toRadixString(16).padLeft(8, '0');
  }

  static int _fnv1a(List<int> units) {
    var hash = 0x811c9dc5;
    for (final unit in units) {
      hash ^= unit & 0xff;
      // hash *= 16777619, kept inside 32 bits via shifts.
      hash = (hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) +
              (hash << 24))) &
          0xffffffff;
    }
    return hash & 0xffffffff;
  }
}
