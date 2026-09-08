export '../widgets/insight_widgets.dart' show InsightNote;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/models/financial_document.dart';
import '../data/models/financial_rule.dart';
import '../services/financial_vault_service.dart';
import 'providers.dart';

final documentsProvider =
    AsyncNotifierProvider<DocumentsNotifier, List<FinancialDocument>>(
  DocumentsNotifier.new,
);

class DocumentsNotifier extends AsyncNotifier<List<FinancialDocument>> {
  @override
  Future<List<FinancialDocument>> build() =>
      ref.watch(dataLayerProvider).documents.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).documents.list(),
    );
  }

  Future<void> upsert(FinancialDocument document) async {
    await ref.read(dataLayerProvider).documents.upsert(document);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).documents.list(),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(dataLayerProvider).documents.delete(id);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).documents.list(),
    );
  }
}

final financialRulesProvider =
    AsyncNotifierProvider<FinancialRulesNotifier, List<FinancialRule>>(
  FinancialRulesNotifier.new,
);

class FinancialRulesNotifier extends AsyncNotifier<List<FinancialRule>> {
  @override
  Future<List<FinancialRule>> build() =>
      ref.watch(dataLayerProvider).financialRules.list();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).financialRules.list(),
    );
  }

  Future<void> upsert(FinancialRule rule) async {
    await ref.read(dataLayerProvider).financialRules.upsert(rule);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).financialRules.list(),
    );
  }

  Future<void> delete(String id) async {
    await ref.read(dataLayerProvider).financialRules.delete(id);
    state = await AsyncValue.guard(
      () => ref.read(dataLayerProvider).financialRules.list(),
    );
  }
}

final financialVaultServiceProvider = Provider<FinancialVaultService>((ref) {
  final data = ref.watch(dataLayerProvider);
  return FinancialVaultService(
    isRemote: data.isRemote,
    client: data.isRemote ? Supabase.instance.client : null,
  );
});
