import 'dart:math' as math;

import 'package:spendwise_parser/spendwise_parser.dart';

import '../data/models/app_transaction.dart';
import '../data/models/financial_rule.dart';

/// A deterministic, private answer calculated from SpendWise's structured
/// transaction data. No financial data is sent to an external AI service.
class FinancialAnswer {
  const FinancialAnswer({
    required this.title,
    required this.body,
    this.metrics = const <FinancialAnswerMetric>[],
    this.followUps = const <String>[],
  });

  final String title;
  final String body;
  final List<FinancialAnswerMetric> metrics;
  final List<String> followUps;
}

class FinancialAnswerMetric {
  const FinancialAnswerMetric.amount(
    this.label,
    this.amountCents, {
    required this.currency,
  }) : textValue = null;

  const FinancialAnswerMetric.text(this.label, this.textValue)
      : amountCents = null,
        currency = null;

  final String label;
  final int? amountCents;
  final String? currency;
  final String? textValue;
}

class FinancialQueryEngine {
  const FinancialQueryEngine();

  FinancialAnswer answer(
    String question, {
    required List<AppTransaction> transactions,
    required List<FinancialRule> rules,
    required String currency,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final query = question.trim();
    final lower = query.toLowerCase();

    if (query.isEmpty) {
      return const FinancialAnswer(
        title: 'Ask about your money',
        body: 'Try a month, merchant, category, investment rule, or spending comparison.',
      );
    }

    if (_containsAny(lower, <String>['mortgage', 'house affordability', 'afford a house'])) {
      return _mortgageAnswer(transactions, rules, currency, clock);
    }

    if (_containsAny(lower, <String>['compare', 'versus', ' vs '])) {
      final comparison = _comparisonAnswer(lower, transactions, rules, currency, clock);
      if (comparison != null) return comparison;
    }

    final window = _windowFor(lower, clock);
    final inWindow = transactions
        .where((t) => t.currency == currency)
        .where((t) => window == null || window.contains(t.occurredAt))
        .toList();

    if (_containsAny(lower, <String>[
      'investment',
      'invested',
      'invest',
      'saving',
      'savings',
    ])) {
      return _ruleKindAnswer(
        FinancialRuleKind.investment,
        'Investments & savings',
        inWindow,
        rules,
        currency,
        window,
      );
    }

    if (_containsAny(lower, <String>['income', 'pay', 'earned', 'salary', 'wage'])) {
      return _ruleKindAnswer(
        FinancialRuleKind.income,
        'Income',
        inWindow,
        rules,
        currency,
        window,
      );
    }

    if (_containsAny(lower, <String>['top merchant', 'biggest merchant', 'where did i spend'])) {
      return _topMerchants(inWindow, rules, currency, window);
    }

    if (_containsAny(lower, <String>['top categor', 'biggest categor'])) {
      return _topCategories(inWindow, rules, currency, window);
    }

    if (_containsAny(lower, <String>['biggest month', 'highest month', 'most expensive month'])) {
      return _biggestMonth(transactions, rules, currency);
    }

    final category = _categoryFrom(lower);
    final merchant = _merchantFrom(lower, transactions);
    var spending = inWindow.where((t) => _isSpending(t, rules)).toList();

    if (category != null) {
      spending = spending.where((t) => t.category == category).toList();
    }
    if (merchant != null) {
      spending = spending.where((t) => _sameMerchant(t, merchant)).toList();
    }

    final total = _sum(spending);
    final average = spending.isEmpty ? 0 : (total / spending.length).round();
    final label = merchant ?? category?.displayName ?? 'Spending';
    final period = window?.label ?? 'all recorded history';

    return FinancialAnswer(
      title: label,
      body: spending.isEmpty
          ? 'I found no matching spending in $period.'
          : 'I found ${spending.length} matching purchase${spending.length == 1 ? '' : 's'} in $period. Financial memory rules are applied before totals are calculated.',
      metrics: <FinancialAnswerMetric>[
        FinancialAnswerMetric.amount('Total', total, currency: currency),
        if (spending.isNotEmpty)
          FinancialAnswerMetric.amount('Average', average, currency: currency),
        FinancialAnswerMetric.text('Transactions', '${spending.length}'),
      ],
      followUps: const <String>[
        'What are my top merchants?',
        'How much did I spend on groceries?',
        'Show my biggest spending month',
      ],
    );
  }

  FinancialAnswer _ruleKindAnswer(
    FinancialRuleKind kind,
    String title,
    List<AppTransaction> transactions,
    List<FinancialRule> rules,
    String currency,
    _QueryWindow? window,
  ) {
    final matching = transactions
        .where((t) => _ruleFor(t, rules)?.kind == kind)
        .toList();
    final total = _sum(matching);
    final period = window?.label ?? 'all recorded history';

    if (matching.isEmpty) {
      return FinancialAnswer(
        title: title,
        body: 'No transactions are classified as ${kind.displayName.toLowerCase()} in $period. Add a Financial Memory rule such as “Wealthsimple → Investment / savings” or an employer name → Income, then ask again.',
        metrics: <FinancialAnswerMetric>[
          FinancialAnswerMetric.amount('Total', 0, currency: currency),
        ],
        followUps: const <String>[
          'How much did I spend this month?',
          'What are my top merchants?',
        ],
      );
    }

    return FinancialAnswer(
      title: title,
      body: '${matching.length} transaction${matching.length == 1 ? '' : 's'} matched your Financial Memory rules in $period.',
      metrics: <FinancialAnswerMetric>[
        FinancialAnswerMetric.amount('Total', total, currency: currency),
        FinancialAnswerMetric.text('Matched transactions', '${matching.length}'),
      ],
      followUps: const <String>[
        'How much did I spend this month?',
        'Show my biggest spending month',
      ],
    );
  }

  FinancialAnswer _topMerchants(
    List<AppTransaction> transactions,
    List<FinancialRule> rules,
    String currency,
    _QueryWindow? window,
  ) {
    final totals = <String, _MerchantTotal>{};
    for (final transaction in transactions.where((t) => _isSpending(t, rules))) {
      final name = transaction.merchant?.trim().isNotEmpty == true
          ? transaction.merchant!.trim()
          : transaction.displayMerchant;
      final key = (transaction.merchantNormalized ?? name).toUpperCase();
      final current = totals[key];
      totals[key] = _MerchantTotal(
        name: current?.name ?? name,
        cents: (current?.cents ?? 0) + transaction.amountCents,
        count: (current?.count ?? 0) + 1,
      );
    }
    final ranked = totals.values.toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));
    final top = ranked.take(5).toList();

    return FinancialAnswer(
      title: 'Top merchants',
      body: top.isEmpty
          ? 'No merchant spending is recorded in ${window?.label ?? 'this selection'}.'
          : 'These merchants account for the most recorded spending in ${window?.label ?? 'this selection'}.',
      metrics: <FinancialAnswerMetric>[
        for (final merchant in top)
          FinancialAnswerMetric.amount(
            '${merchant.name} · ${merchant.count}x',
            merchant.cents,
            currency: currency,
          ),
      ],
      followUps: const <String>[
        'How much did I spend on groceries?',
        'Show my biggest spending month',
      ],
    );
  }

  FinancialAnswer _topCategories(
    List<AppTransaction> transactions,
    List<FinancialRule> rules,
    String currency,
    _QueryWindow? window,
  ) {
    final totals = <SpendCategory, int>{};
    for (final transaction in transactions.where((t) => _isSpending(t, rules))) {
      totals[transaction.category] =
          (totals[transaction.category] ?? 0) + transaction.amountCents;
    }
    final ranked = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return FinancialAnswer(
      title: 'Top categories',
      body: ranked.isEmpty
          ? 'No category spending is recorded in ${window?.label ?? 'this selection'}.'
          : 'Your largest spending categories in ${window?.label ?? 'this selection'} are below.',
      metrics: <FinancialAnswerMetric>[
        for (final entry in ranked.take(5))
          FinancialAnswerMetric.amount(
            entry.key.displayName,
            entry.value,
            currency: currency,
          ),
      ],
      followUps: const <String>[
        'What are my top merchants?',
        'How much did I spend this month?',
      ],
    );
  }

  FinancialAnswer _biggestMonth(
    List<AppTransaction> transactions,
    List<FinancialRule> rules,
    String currency,
  ) {
    final totals = <String, _MonthTotal>{};
    for (final transaction in transactions
        .where((t) => t.currency == currency)
        .where((t) => _isSpending(t, rules))) {
      final key = '${transaction.occurredAt.year}-${transaction.occurredAt.month.toString().padLeft(2, '0')}';
      final current = totals[key];
      totals[key] = _MonthTotal(
        year: transaction.occurredAt.year,
        month: transaction.occurredAt.month,
        cents: (current?.cents ?? 0) + transaction.amountCents,
      );
    }
    if (totals.isEmpty) {
      return const FinancialAnswer(
        title: 'Biggest spending month',
        body: 'There is not enough recorded spending to compare months yet.',
      );
    }

    final ranked = totals.values.toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));
    final biggest = ranked.first;
    return FinancialAnswer(
      title: 'Biggest spending month',
      body: '${_monthNames[biggest.month - 1]} ${biggest.year} is the highest recorded month after Financial Memory rules are applied.',
      metrics: <FinancialAnswerMetric>[
        FinancialAnswerMetric.amount('Spent', biggest.cents, currency: currency),
        if (ranked.length > 1)
          FinancialAnswerMetric.amount(
            'Next highest · ${_monthNames[ranked[1].month - 1]} ${ranked[1].year}',
            ranked[1].cents,
            currency: currency,
          ),
      ],
      followUps: const <String>[
        'What are my top merchants?',
        'How much did I spend on groceries?',
      ],
    );
  }

  FinancialAnswer? _comparisonAnswer(
    String lower,
    List<AppTransaction> transactions,
    List<FinancialRule> rules,
    String currency,
    DateTime now,
  ) {
    final months = _mentionedMonths(lower).toList();
    if (months.length < 2) return null;

    final year = _mentionedYear(lower) ?? now.year;
    final first = months[0];
    final second = months[1];
    int totalFor(int month) => _sum(
          transactions
              .where((t) => t.currency == currency)
              .where((t) => t.occurredAt.year == year && t.occurredAt.month == month)
              .where((t) => _isSpending(t, rules)),
        );
    final a = totalFor(first);
    final b = totalFor(second);
    final difference = b - a;
    final percent = a == 0 ? null : difference / a;

    return FinancialAnswer(
      title: '${_monthNames[first - 1]} vs ${_monthNames[second - 1]}',
      body: difference == 0
          ? 'Recorded spending was the same in both months.'
          : '${_monthNames[second - 1]} was ${difference > 0 ? 'higher' : 'lower'} by ${difference.abs()} cents before formatting. The amount cards below show the exact currency totals.${percent == null ? '' : ' That is ${(percent.abs() * 100).toStringAsFixed(1)}% ${difference > 0 ? 'more' : 'less'}.'}',
      metrics: <FinancialAnswerMetric>[
        FinancialAnswerMetric.amount(
          '${_monthNames[first - 1]} $year',
          a,
          currency: currency,
        ),
        FinancialAnswerMetric.amount(
          '${_monthNames[second - 1]} $year',
          b,
          currency: currency,
        ),
        FinancialAnswerMetric.amount(
          'Difference',
          difference.abs(),
          currency: currency,
        ),
      ],
    );
  }

  FinancialAnswer _mortgageAnswer(
    List<AppTransaction> transactions,
    List<FinancialRule> rules,
    String currency,
    DateTime now,
  ) {
    final start = DateTime(now.year, now.month - 5, 1);
    final monthly = <String, int>{};
    for (final transaction in transactions
        .where((t) => t.currency == currency)
        .where((t) => !t.occurredAt.isBefore(start))
        .where((t) => _isSpending(t, rules))) {
      final key = '${transaction.occurredAt.year}-${transaction.occurredAt.month}';
      monthly[key] = (monthly[key] ?? 0) + transaction.amountCents;
    }
    final baseline = monthly.isEmpty
        ? 0
        : (monthly.values.reduce((a, b) => a + b) / monthly.length).round();

    return FinancialAnswer(
      title: 'Mortgage readiness',
      body: 'SpendWise can show your recorded spending baseline, but the current transaction model does not yet reliably identify every household income source, debt payment, account balance, interest rate, property tax, or down payment. It would be irresponsible to turn spending alone into a mortgage approval figure.',
      metrics: <FinancialAnswerMetric>[
        if (baseline > 0)
          FinancialAnswerMetric.amount(
            'Recent recorded spending / month',
            baseline,
            currency: currency,
          ),
      ],
      followUps: const <String>[
        'How much did I spend this month?',
        'Show my biggest spending month',
        'How much did my investment rules capture?',
      ],
    );
  }

  bool _isSpending(AppTransaction transaction, List<FinancialRule> rules) {
    final rule = _ruleFor(transaction, rules);
    if (rule != null) {
      switch (rule.kind) {
        case FinancialRuleKind.expense:
          return transaction.amountCents > 0;
        case FinancialRuleKind.investment:
        case FinancialRuleKind.income:
        case FinancialRuleKind.internalTransfer:
        case FinancialRuleKind.exclude:
          return false;
      }
    }
    return transaction.countsAsSpending;
  }

  FinancialRule? _ruleFor(
    AppTransaction transaction,
    List<FinancialRule> rules,
  ) {
    final values = <String>[
      if (transaction.merchant != null) transaction.merchant!,
      if (transaction.merchantNormalized != null) transaction.merchantNormalized!,
      if (transaction.note != null) transaction.note!,
      transaction.displayMerchant,
    ];
    FinancialRule? winner;
    for (final rule in rules.where((r) => r.enabled)) {
      if (values.any(rule.matches) &&
          (winner == null || rule.pattern.length > winner.pattern.length)) {
        winner = rule;
      }
    }
    return winner;
  }

  String? _merchantFrom(String lower, List<AppTransaction> transactions) {
    String? winner;
    for (final transaction in transactions) {
      final candidates = <String?>[
        transaction.merchant,
        transaction.merchantNormalized,
      ];
      for (final candidate in candidates) {
        final value = candidate?.trim();
        if (value == null || value.length < 3) continue;
        if (lower.contains(value.toLowerCase()) &&
            (winner == null || value.length > winner.length)) {
          winner = value;
        }
      }
    }
    return winner;
  }

  bool _sameMerchant(AppTransaction transaction, String merchant) {
    final wanted = merchant.toUpperCase();
    return transaction.merchant?.toUpperCase() == wanted ||
        transaction.merchantNormalized?.toUpperCase() == wanted;
  }

  SpendCategory? _categoryFrom(String lower) {
    const aliases = <SpendCategory, List<String>>{
      SpendCategory.groceries: <String>['grocery', 'groceries', 'food shopping'],
      SpendCategory.dining: <String>['dining', 'restaurant', 'restaurants', 'takeout'],
      SpendCategory.gas: <String>['gas', 'fuel'],
      SpendCategory.transportation: <String>['transportation', 'transport', 'taxi', 'rides'],
      SpendCategory.shopping: <String>['shopping'],
      SpendCategory.utilities: <String>['utilities', 'utility', 'power', 'electricity'],
      SpendCategory.phoneInternet: <String>['phone', 'internet', 'mobile'],
      SpendCategory.subscriptions: <String>['subscription', 'subscriptions'],
      SpendCategory.housing: <String>['housing', 'rent'],
      SpendCategory.health: <String>['health', 'medical', 'pharmacy'],
      SpendCategory.entertainment: <String>['entertainment', 'movies', 'gaming'],
    };
    for (final entry in aliases.entries) {
      if (entry.value.any(lower.contains)) return entry.key;
    }
    return null;
  }

  _QueryWindow? _windowFor(String lower, DateTime now) {
    if (lower.contains('this month') || lower.contains('current month')) {
      final start = DateTime(now.year, now.month, 1);
      return _QueryWindow(start, DateTime(now.year, now.month + 1, 1), 'this month');
    }
    if (lower.contains('last month') || lower.contains('previous month')) {
      final start = DateTime(now.year, now.month - 1, 1);
      return _QueryWindow(start, DateTime(now.year, now.month, 1), 'last month');
    }
    if (lower.contains('this year')) {
      return _QueryWindow(DateTime(now.year, 1, 1), DateTime(now.year + 1, 1, 1), '${now.year}');
    }

    final months = _mentionedMonths(lower).toList()..sort();
    if (months.isNotEmpty) {
      final year = _mentionedYear(lower) ?? now.year;
      final first = months.first;
      final last = months.last;
      final label = first == last
          ? '${_monthNames[first - 1]} $year'
          : '${_monthNames[first - 1]}–${_monthNames[last - 1]} $year';
      return _QueryWindow(
        DateTime(year, first, 1),
        DateTime(year, last + 1, 1),
        label,
      );
    }

    final year = _mentionedYear(lower);
    if (year != null) {
      return _QueryWindow(DateTime(year, 1, 1), DateTime(year + 1, 1, 1), '$year');
    }
    return null;
  }

  Iterable<int> _mentionedMonths(String lower) sync* {
    final found = <int>{};
    for (var index = 0; index < _monthNames.length; index++) {
      final full = _monthNames[index].toLowerCase();
      final short = full.substring(0, math.min(3, full.length));
      final pattern = RegExp('(?:^|[^a-z])(?:$full|$short)(?:[^a-z]|\$)');
      if (pattern.hasMatch(lower)) found.add(index + 1);
    }
    yield* found;
  }

  int? _mentionedYear(String lower) {
    final match = RegExp(r'\b(20\d{2})\b').firstMatch(lower);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int _sum(Iterable<AppTransaction> transactions) => transactions.fold<int>(
        0,
        (sum, transaction) => sum + transaction.amountCents,
      );

  bool _containsAny(String value, List<String> needles) =>
      needles.any(value.contains);

  static const _monthNames = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
}

class _QueryWindow {
  const _QueryWindow(this.start, this.end, this.label);
  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);
}

class _MerchantTotal {
  const _MerchantTotal({required this.name, required this.cents, required this.count});
  final String name;
  final int cents;
  final int count;
}

class _MonthTotal {
  const _MonthTotal({required this.year, required this.month, required this.cents});
  final int year;
  final int month;
  final int cents;
}