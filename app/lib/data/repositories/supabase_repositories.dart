import 'package:spendwise_parser/spendwise_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/budget.dart';
import '../models/user_preferences.dart';
import 'repositories.dart';

/// Supabase-backed storage.
///
/// None of these methods filter by user id. That is deliberate: Row Level
/// Security does it in the database, so a client bug cannot leak another
/// user's rows and cannot write a row it does not own. The `user_id` column
/// defaults to `auth.uid()` server-side, so it is never sent from here.
class SupabaseData {
  static DataLayer open(SupabaseClient client) => DataLayer(
        transactions: SupabaseTransactionRepository(client),
        accounts: SupabaseAccountRepository(client),
        budgets: SupabaseBudgetRepository(client),
        rules: SupabaseRuleRepository(client),
        preferences: SupabasePreferencesRepository(client),
        isRemote: true,
      );
}

/// Supabase returns `List<Map<String, dynamic>>`; the models want
/// `Map<String, Object?>`. One conversion point keeps the casts out of
/// every repository.
List<Map<String, Object?>> _rows(List<Map<String, dynamic>> raw) =>
    raw.map((r) => Map<String, Object?>.from(r)).toList();

class SupabaseTransactionRepository implements TransactionRepository {
  SupabaseTransactionRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to}) async {
    var query = _client.from('transactions').select();
    if (from != null) {
      query = query.gte('occurred_at', from.toUtc().toIso8601String());
    }
    if (to != null) {
      query = query.lt('occurred_at', to.toUtc().toIso8601String());
    }
    final response = await query.order('occurred_at', ascending: false);
    return _rows(response).map(AppTransaction.fromJson).toList();
  }

  @override
  Future<void> upsert(AppTransaction transaction) async {
    await _client.from('transactions').upsert(transaction.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('transactions').delete().eq('id', id);
  }
}

class SupabaseAccountRepository implements AccountRepository {
  SupabaseAccountRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Account>> list() async {
    final response = await _client.from('accounts').select().order('label');
    return _rows(response).map(Account.fromJson).toList();
  }

  @override
  Future<void> upsert(Account account) async {
    await _client.from('accounts').upsert(account.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('accounts').delete().eq('id', id);
  }
}

class SupabaseBudgetRepository implements BudgetRepository {
  SupabaseBudgetRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Budget>> list() async {
    final response = await _client.from('budgets').select();
    return _rows(response).map(Budget.fromJson).toList();
  }

  @override
  Future<void> upsert(Budget budget) async {
    await _client.from('budgets').upsert(budget.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('budgets').delete().eq('id', id);
  }
}

class SupabaseRuleRepository implements MerchantRuleRepository {
  SupabaseRuleRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<List<MerchantRule>> list() async {
    final response = await _client.from('merchant_rules').select();
    return _rows(response).map(MerchantRule.fromJson).toList();
  }

  @override
  Future<void> upsert(MerchantRule rule) async {
    await _client.from('merchant_rules').upsert(rule.toJson());
  }

  @override
  Future<void> delete(String id) async {
    await _client.from('merchant_rules').delete().eq('id', id);
  }
}

class SupabasePreferencesRepository implements PreferencesRepository {
  SupabasePreferencesRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<UserPreferences> load() async {
    final response =
        await _client.from('user_preferences').select().maybeSingle();
    if (response == null) return const UserPreferences();
    return UserPreferences.fromJson(Map<String, Object?>.from(response));
  }

  @override
  Future<void> save(UserPreferences preferences) async {
    // One preferences row per user, keyed by user_id, so upsert must target
    // that column rather than a synthetic primary key.
    await _client
        .from('user_preferences')
        .upsert(preferences.toJson(), onConflict: 'user_id');
  }
}
