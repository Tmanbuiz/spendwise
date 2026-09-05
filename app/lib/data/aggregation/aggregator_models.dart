import 'package:spendwise_parser/spendwise_parser.dart';

/// Which data aggregator a linked account came from.
///
/// Provider-neutral by design: Plaid ships a Flutter SDK so it is implemented
/// first, but Flinks has stronger Canadian coverage and may replace or join
/// it. Nothing outside the client layer knows which one is in use.
enum AggregatorProvider {
  plaid('Plaid'),
  flinks('Flinks');

  const AggregatorProvider(this.displayName);
  final String displayName;
}

/// A bank connection the user has authorised.
///
/// Note what is absent: no credentials, no access token. The access token
/// lives server-side in the Edge Function and is never sent to the device —
/// possessing it would let the app pull the account without the user present.
class LinkedItem {
  const LinkedItem({
    required this.id,
    required this.provider,
    required this.institutionName,
    required this.linkedAt,
    this.lastSyncedAt,
    this.needsReauth = false,
  });

  final String id;
  final AggregatorProvider provider;
  final String institutionName;
  final DateTime linkedAt;
  final DateTime? lastSyncedAt;

  /// Bank connections expire and need the user to re-authorise. Surfacing
  /// this beats silently stopping the sync.
  final bool needsReauth;

  static LinkedItem fromJson(Map<String, Object?> json) => LinkedItem(
        id: (json['id'] as String?) ?? '',
        provider: AggregatorProvider.values.firstWhere(
          (p) => p.name == json['provider'],
          orElse: () => AggregatorProvider.plaid,
        ),
        institutionName:
            (json['institution_name'] as String?) ?? 'Linked bank',
        linkedAt: DateTime.tryParse((json['linked_at'] as String?) ?? '') ??
            DateTime.now(),
        lastSyncedAt:
            DateTime.tryParse((json['last_synced_at'] as String?) ?? ''),
        needsReauth: (json['needs_reauth'] as bool?) ?? false,
      );
}

/// One transaction as delivered by an aggregator, normalised across providers.
class AggregatorTransaction {
  const AggregatorTransaction({
    required this.providerId,
    required this.amountCents,
    required this.currency,
    required this.date,
    required this.eventType,
    this.merchant,
    this.accountLast4,
    this.accountId,
    this.category,
    this.isPending = false,
  });

  /// The aggregator's own stable id. Used so re-syncing the same transaction
  /// updates rather than duplicates it.
  final String providerId;

  /// Always positive; direction is carried by [eventType], matching the
  /// convention the rest of the app uses.
  final int amountCents;
  final String currency;

  /// Posting date. Aggregators usually give a date, not a timestamp.
  final DateTime date;

  final TransactionEventType eventType;
  final String? merchant;
  final String? accountLast4;
  final String? accountId;

  /// The aggregator's own category, if it gave one. Only a hint — SpendWise's
  /// own rules and the user's overrides take precedence.
  final SpendCategory? category;

  /// Pending transactions can change amount before they post, which is why
  /// reconciliation tolerates an amount drift.
  final bool isPending;

  String? get merchantNormalized => MerchantExtractor.normalize(merchant);
}
