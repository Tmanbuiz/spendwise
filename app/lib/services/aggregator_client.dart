import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/aggregation/aggregator_models.dart';

/// Talks to a bank data aggregator.
///
/// Every call goes through a Supabase Edge Function rather than to the
/// provider directly. That is not indirection for its own sake: Plaid's and
/// Flinks' secrets grant the ability to pull a linked account without the user
/// present, so they must never ship inside the app where anyone can extract
/// them from the APK. The device only ever handles short-lived link tokens.
abstract interface class AggregatorClient {
  /// False when no aggregator is set up. The UI hides the feature rather than
  /// offering a button that cannot work.
  bool get isConfigured;

  /// A short-lived token that opens the provider's Link UI.
  Future<String> createLinkToken();

  /// Trades the public token the Link UI returns for a durable connection.
  /// The access token itself stays server-side.
  Future<LinkedItem> exchangePublicToken(String publicToken);

  Future<List<LinkedItem>> listItems();

  /// Pulls transactions for every linked account.
  Future<List<AggregatorTransaction>> fetchTransactions({DateTime? since});

  /// Revokes a connection at the provider and forgets it.
  Future<void> unlink(String itemId);
}

/// Aggregator client backed by Supabase Edge Functions.
class SupabaseAggregatorClient implements AggregatorClient {
  const SupabaseAggregatorClient({
    required this.enabled,
    this.clientOverride,
  });

  /// Set from config. Without a Supabase project there is nowhere to host the
  /// functions, so the feature stays off.
  final bool enabled;

  /// Injected in tests; production reads the singleton.
  final SupabaseClient? clientOverride;

  SupabaseClient get _supabase => clientOverride ?? Supabase.instance.client;

  @override
  bool get isConfigured => enabled;

  Future<Map<String, Object?>> _invoke(
    String function, [
    Map<String, Object?>? body,
  ]) async {
    final response = await _supabase.functions.invoke(function, body: body);
    final data = response.data;
    if (data is Map) return Map<String, Object?>.from(data);
    return <String, Object?>{};
  }

  @override
  Future<String> createLinkToken() async {
    final data = await _invoke('aggregator-link-token');
    final token = data['link_token'] as String?;
    if (token == null || token.isEmpty) {
      throw StateError('No link token returned');
    }
    return token;
  }

  @override
  Future<LinkedItem> exchangePublicToken(String publicToken) async {
    final data = await _invoke(
      'aggregator-exchange-token',
      <String, Object?>{'public_token': publicToken},
    );
    return LinkedItem.fromJson(data);
  }

  @override
  Future<List<LinkedItem>> listItems() async {
    // The token-free view, not the base table: `linked_items` deliberately
    // grants the client no SELECT, so the access token cannot be queried.
    final rows = await _supabase.from('linked_items_public').select();
    return rows
        .map((r) => LinkedItem.fromJson(Map<String, Object?>.from(r)))
        .toList();
  }

  @override
  Future<List<AggregatorTransaction>> fetchTransactions({
    DateTime? since,
  }) async {
    final data = await _invoke(
      'aggregator-sync',
      <String, Object?>{
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );

    if (data['partial_failure'] == true) {
      throw StateError('One or more banks could not sync. Retry or reconnect the affected bank.');
    }
    final rows = data['transactions'];
    if (rows is! List) return const <AggregatorTransaction>[];

    return rows
        .whereType<Map<Object?, Object?>>()
        .map((r) => parseAggregatorTransaction(Map<String, Object?>.from(r)))
        .whereType<AggregatorTransaction>()
        .toList();
  }

  @override
  Future<void> unlink(String itemId) async {
    await _invoke(
      'aggregator-unlink',
      <String, Object?>{'item_id': itemId},
    );
  }
}

/// Converts one row from the sync function into an [AggregatorTransaction].
///
/// The Edge Function has already normalised provider quirks into this shape,
/// so this only has to survive bad data — a malformed row returns null rather
/// than throwing, because one bad record must not abort an entire sync.
AggregatorTransaction? parseAggregatorTransaction(Map<String, Object?> json) {
  try { return _parseAggregatorTransaction(json); } on Object { return null; }
}
AggregatorTransaction? _parseAggregatorTransaction(Map<String, Object?> json) {
  final providerId = json['provider_id'] as String?;
  if (providerId == null || providerId.isEmpty) return null;

  final cents = (json['amount_cents'] as num?)?.toInt();
  if (cents == null || !(json['amount_cents'] as num).isFinite || (json['amount_cents'] as num) != (json['amount_cents'] as num).roundToDouble()) return null;

  final date = DateTime.tryParse((json['date'] as String?) ?? '');
  if (date == null) return null;

  final categorySlug = json['category'] as String?;

  return AggregatorTransaction(
    providerId: providerId,
    // Direction is carried by the event type, so the magnitude is stored.
    amountCents: cents.abs(),
    currency: ((json['currency'] as String?) ?? 'CAD').toUpperCase(),
    date: date.toLocal(),
    eventType: TransactionEventType.fromWireName(
      (json['event_type'] as String?) ?? 'unknown',
    ),
    merchant: json['merchant'] as String?,
    accountLast4: json['account_last4'] as String?,
    accountId: json['account_id'] as String?,
    category:
        categorySlug == null ? null : SpendCategory.fromSlug(categorySlug),
    isPending: (json['is_pending'] as bool?) ?? false,
  );
}
