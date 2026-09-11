import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/ei/ei_config.dart';
import '../data/ei/ei_dates.dart';
import '../data/ei/ei_hours_engine.dart';
import '../data/ei/ei_models.dart';
import '../data/ei/ei_payroll_detection.dart';
import '../data/models/app_transaction.dart';
import '../data/models/financial_document.dart';
import 'financial_providers.dart';
import 'providers.dart';

/// Today, as a date. Overridden in tests so estimates do not drift with the
/// clock.
final eiTodayProvider = Provider<DateTime>(
  (ref) => EiDates.day(DateTime.now()),
);

final eiEngineProvider = Provider<EiHoursEngine>(
  (ref) => const EiHoursEngine(),
);

final eiTrackerProvider =
    AsyncNotifierProvider<EiTrackerNotifier, EiTrackerData>(
      EiTrackerNotifier.new,
    );

/// The hours tracker's data, kept on this device like recurring bills and
/// carried in backups.
///
/// A save that cannot be read back is reported as an error rather than
/// replaced with an empty tracker, so a bug never quietly wipes someone's
/// hours.
class EiTrackerNotifier extends AsyncNotifier<EiTrackerData> {
  static const key = 'spendwise.ei_hours';

  @override
  Future<EiTrackerData> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const EiTrackerData();
    return EiTrackerData.decode(raw);
  }

  Future<void> save(EiTrackerData data) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(key, data.encode())) {
      throw StateError('Could not save EI hours');
    }
    state = AsyncData(data);
  }

  /// Applies [update] to the latest saved data and saves the result.
  Future<void> change(EiTrackerData Function(EiTrackerData) update) async {
    final current = await future;
    await save(update(current));
  }
}

/// The estimate for what has been entered, or null while it loads.
final eiEstimateProvider = Provider<EiHoursEstimate?>((ref) {
  final data = ref.watch(eiTrackerProvider).value;
  if (data == null) return null;
  return ref
      .watch(eiEngineProvider)
      .estimate(data, today: ref.watch(eiTodayProvider));
});

/// Payroll deposits in the user's transactions over the last two qualifying
/// periods, used to suggest employers and pay schedules.
final eiPayrollPatternsProvider = Provider<List<EiPayrollPattern>>((ref) {
  final transactions =
      ref.watch(transactionsProvider).value ?? const <AppTransaction>[];
  return EiPayrollDetector.detect(
    transactions,
    since: EiDates.addDays(
      ref.watch(eiTodayProvider),
      -2 * EiConfig.rules.qualifyingPeriodDays,
    ),
  );
});

/// Pay stubs kept in the Financial Vault, newest first.
final eiPayStubsProvider = Provider<List<FinancialDocument>>((ref) {
  final documents =
      ref.watch(documentsProvider).value ?? const <FinancialDocument>[];
  return documents
      .where((d) => d.documentType == FinancialDocumentType.payStub)
      .toList();
});
