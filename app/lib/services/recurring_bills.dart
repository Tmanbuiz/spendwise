import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/providers.dart';
import '../data/repositories/local_repositories.dart';
import '../data/repositories/repositories.dart';

class RecurringBill {
  const RecurringBill({
    required this.id,
    required this.name,
    required this.cents,
    required this.currency,
    required this.due,
    required this.frequency,
    required this.anchorDay,
  });
  final String id, name, currency, frequency;
  final int cents, anchorDay;
  final DateTime due;
  DateTime get nextDue {
    if (frequency == 'weekly') {
      return DateTime(due.year, due.month, due.day + 7);
    }
    final month = due.month + (frequency == 'yearly' ? 12 : 1);
    return DateTime(
      due.year,
      month,
      min(anchorDay, DateTime(due.year, month + 1, 0).day),
    );
  }

  RecurringBill advance() => RecurringBill(
    id: id,
    name: name,
    cents: cents,
    currency: currency,
    due: nextDue,
    frequency: frequency,
    anchorDay: anchorDay,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'cents': cents,
    'currency': currency,
    'due': due.toIso8601String(),
    'frequency': frequency,
    'anchorDay': anchorDay,
  };
  static RecurringBill fromJson(Map<String, dynamic> j) {
    final bill = RecurringBill(
      id: j['id'] as String,
      name: j['name'] as String,
      cents: j['cents'] as int,
      currency: j['currency'] as String,
      due: DateTime.parse(j['due'] as String),
      frequency: j['frequency'] as String,
      anchorDay: j['anchorDay'] as int,
    );
    if (bill.id.isEmpty ||
        bill.name.trim().isEmpty ||
        bill.cents <= 0 ||
        bill.anchorDay < 1 ||
        bill.anchorDay > 31 ||
        !['weekly', 'monthly', 'yearly'].contains(bill.frequency) ||
        !RegExp(r'^[A-Z]{3}$').hasMatch(bill.currency)) {
      throw const FormatException('Invalid recurring bill');
    }
    return bill;
  }
}

final billsProvider = AsyncNotifierProvider<BillsNotifier, List<RecurringBill>>(
  BillsNotifier.new,
);

class BillsNotifier extends AsyncNotifier<List<RecurringBill>> {
  static const key = 'spendwise.recurring_bills';
  late DataLayer _storage;
  @override
  Future<List<RecurringBill>> build() async {
    final data = ref.watch(dataLayerProvider);
    _storage = data.readBills != null ? data : await LocalStore.open();
    return (await _storage.readBills!()).map(RecurringBill.fromJson).toList();
  }
  Future<void> save(List<RecurringBill> bills) async {
    await _storage.writeBills!(bills.map((b) => b.toJson()).toList());
    state = AsyncData(bills);
  }
}
