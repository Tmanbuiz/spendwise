import 'package:spendwise_parser/spendwise_parser.dart';

import '../models/account.dart';
import '../models/app_transaction.dart';
import '../models/budget.dart';
import '../models/financial_document.dart';
import '../models/financial_rule.dart';
import '../models/user_preferences.dart';

/// Storage contracts.
///
/// Every screen depends on these interfaces, never on Supabase directly. That
/// is what lets the app run against device-local storage before a Supabase
/// project exists, and what makes the pipeline testable.
abstract interface class TransactionRepository {
  Future<List<AppTransaction>> list({DateTime? from, DateTime? to});
  Future<void> upsert(AppTransaction transaction);
  Future<void> delete(String id);
}

abstract interface class AccountRepository {
  Future<List<Account>> list();
  Future<void> upsert(Account account);
  Future<void> delete(String id);
}

abstract interface class BudgetRepository {
  Future<List<Budget>> list();
  Future<void> upsert(Budget budget);
  Future<void> delete(String id);
}

abstract interface class MerchantRuleRepository {
  Future<List<MerchantRule>> list();
  Future<void> upsert(MerchantRule rule);
  Future<void> delete(String id);
}

abstract interface class FinancialDocumentRepository {
  Future<List<FinancialDocument>> list();
  Future<void> upsert(FinancialDocument document);
  Future<void> delete(String id);
}

abstract interface class FinancialRuleRepository {
  Future<List<FinancialRule>> list();
  Future<void> upsert(FinancialRule rule);
  Future<void> delete(String id);
}

abstract interface class PreferencesRepository {
  Future<UserPreferences> load();
  Future<void> save(UserPreferences preferences);
}

/// The set of repositories the app runs against.
class DataLayer {
  const DataLayer({
    required this.transactions,
    required this.accounts,
    required this.budgets,
    required this.rules,
    required this.documents,
    required this.financialRules,
    required this.preferences,
    required this.isRemote,
  });

  final TransactionRepository transactions;
  final AccountRepository accounts;
  final BudgetRepository budgets;
  final MerchantRuleRepository rules;
  final FinancialDocumentRepository documents;
  final FinancialRuleRepository financialRules;
  final PreferencesRepository preferences;

  /// False when running against the local store, so the UI can say so rather
  /// than letting the user believe their data is synced.
  final bool isRemote;
}
