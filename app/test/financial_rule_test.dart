import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/models/financial_rule.dart';

void main() {
  group('FinancialRule', () {
    test('matches contains without case sensitivity', () {
      const rule = FinancialRule(
        id: 'r1',
        pattern: 'wealthsimple',
        kind: FinancialRuleKind.investment,
      );

      expect(rule.matches('WEALTHSIMPLE INVESTMENTS INC.'), isTrue);
      expect(rule.matches('CIBC SECURITIES'), isFalse);
    });

    test('supports exact, startsWith, and regex', () {
      const exact = FinancialRule(
        id: 'r1',
        pattern: 'HARMONY FAMILY',
        kind: FinancialRuleKind.income,
        match: FinancialRuleMatch.exact,
      );
      const starts = FinancialRule(
        id: 'r2',
        pattern: 'CIBC',
        kind: FinancialRuleKind.investment,
        match: FinancialRuleMatch.startsWith,
      );
      const regex = FinancialRule(
        id: 'r3',
        pattern: r'BEYOND\s+BEHAV',
        kind: FinancialRuleKind.income,
        match: FinancialRuleMatch.regex,
      );

      expect(exact.matches('harmony family'), isTrue);
      expect(starts.matches('CIBC Securities Inc.'), isTrue);
      expect(regex.matches('Beyond Behavioural Interv'), isTrue);
    });

    test('invalid regex fails safely and disabled rules never match', () {
      const invalid = FinancialRule(
        id: 'r1',
        pattern: '[',
        kind: FinancialRuleKind.exclude,
        match: FinancialRuleMatch.regex,
      );
      const disabled = FinancialRule(
        id: 'r2',
        pattern: 'Walmart',
        kind: FinancialRuleKind.expense,
        enabled: false,
      );

      expect(invalid.matches('anything'), isFalse);
      expect(disabled.matches('Walmart'), isFalse);
    });

    test('round trips through json', () {
      const original = FinancialRule(
        id: 'r1',
        pattern: 'Spouse transfer',
        kind: FinancialRuleKind.internalTransfer,
        match: FinancialRuleMatch.contains,
        ownerLabel: 'Household',
        note: 'Do not double count',
      );

      final decoded = FinancialRule.fromJson(original.toJson());
      expect(decoded.id, original.id);
      expect(decoded.pattern, original.pattern);
      expect(decoded.kind, original.kind);
      expect(decoded.match, original.match);
      expect(decoded.ownerLabel, original.ownerLabel);
      expect(decoded.note, original.note);
      expect(decoded.enabled, isTrue);
    });
  });
}
