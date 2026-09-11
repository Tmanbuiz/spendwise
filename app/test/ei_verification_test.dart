import 'package:flutter_test/flutter_test.dart';
import 'package:spendwise/data/ei/ei_config.dart';
import 'package:spendwise/data/ei/ei_hours_engine.dart';
import 'package:spendwise/data/ei/ei_models.dart';
import 'package:spendwise/data/ei/ei_verification.dart';
import 'package:spendwise/data/models/app_transaction.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

DateTime d(int year, int month, int day) => DateTime.utc(year, month, day);

AppTransaction deposit(
  String id,
  DateTime day,
  int cents, {
  String merchant = 'PAY HARMONY FAMILY',
}) => AppTransaction(
  id: id,
  eventType: TransactionEventType.transfer,
  amountCents: cents,
  currency: 'CAD',
  occurredAt: DateTime(day.year, day.month, day.day, 6),
  category: SpendCategory.other,
  source: TransactionSource.statement,
  merchant: merchant,
);

EiHoursRecord stub(
  String id,
  DateTime start,
  DateTime end,
  double hours, {
  DateTime? payDate,
  int? gross,
  int? tax,
  int? cpp,
  int? ei,
  int? other,
  int? net,
}) => EiHoursRecord(
  id: id,
  jobId: 'a',
  periodStart: start,
  periodEnd: end,
  hoursWorked: hours,
  source: EiHoursSource.payStub,
  payStub: EiPayStubDetails(
    payDate: payDate,
    grossPayCents: gross,
    incomeTaxCents: tax,
    cppCents: cpp,
    eiPremiumCents: ei,
    otherDeductionsCents: other,
    netPayCents: net,
  ),
);

final job = EiJob(
  id: 'a',
  employerName: 'Harmony Family',
  startDate: d(2026, 8, 3),
  usualWeeklyHours: 40,
);

/// A complete stub for August 3 to 16, paid August 21: $2,000.00 gross less
/// $500.00 of deductions is $1,500.00 net.
EiHoursRecord august({int net = 150000, int ei = 3260, DateTime? payDate}) =>
    stub(
      's1',
      d(2026, 8, 3),
      d(2026, 8, 16),
      80,
      payDate: payDate ?? d(2026, 8, 21),
      gross: 200000,
      tax: 30000,
      cpp: 11000,
      ei: ei,
      other: 5740,
      net: net,
    );

EiVerification verify(
  List<EiHoursRecord> records,
  List<AppTransaction> transactions,
) {
  final data = EiTrackerData(
    plannedClaimStart: d(2027, 1, 15),
    jobs: [job],
    records: records,
  );
  final estimate = const EiHoursEngine().estimate(data, today: d(2026, 9, 11));
  return EiVerifier.verify(
    data: data,
    estimate: estimate,
    transactions: transactions,
  );
}

void main() {
  group('a pay stub against itself', () {
    test('gross less deductions is the net pay', () {
      final details = august().payStub!;
      expect(details.totalDeductionsCents, 50000);
      expect(details.calculatedNetCents, 150000);

      final check = verify([august()], const []).checkFor('s1')!;
      expect(check.netPayMismatchCents, isNull);
      expect(check.eiPremiumMissing, isFalse);
    });

    test('net pay that does not add up is flagged, rounding is not', () {
      expect(
        verify([august(net: 151000)], const []).checkFor('s1')!
            .netPayMismatchCents,
        1000,
      );
      expect(
        verify([august(net: 150001)], const []).checkFor('s1')!
            .netPayMismatchCents,
        isNull,
      );
    });

    test('a stub with no EI premium is flagged', () {
      expect(
        verify([august(ei: 0, net: 153260)], const []).checkFor('s1')!
            .eiPremiumMissing,
        isTrue,
      );
      // A premium left blank is unknown, not missing.
      final blank = stub('s1', d(2026, 8, 3), d(2026, 8, 16), 80, gross: 1);
      expect(verify([blank], const []).checkFor('s1')!.eiPremiumMissing, isFalse);
    });
  });

  group('a pay stub against the bank', () {
    test('the net pay deposited on payday verifies it', () {
      final result = verify(
        [august()],
        [deposit('t1', d(2026, 8, 21), 150000)],
      );
      final check = result.checkFor('s1')!;
      expect(check.match, EiDepositMatch.matched);
      expect(check.deposit!.id, 't1');
      expect(result.problems, isEmpty);
    });

    test('a deposit a little early or late matches; a week off or a cent '
        'different does not', () {
      EiDepositMatch matchWith(AppTransaction transaction) =>
          verify([august()], [transaction]).checkFor('s1')!.match;

      expect(
        matchWith(deposit('early', d(2026, 8, 19), 150000)),
        EiDepositMatch.matched,
      );
      expect(
        matchWith(deposit('weekend', d(2026, 8, 24), 150000)),
        EiDepositMatch.matched,
      );
      expect(
        matchWith(deposit('week', d(2026, 8, 28), 150000)),
        EiDepositMatch.notFound,
      );
      expect(
        matchWith(deposit('cent', d(2026, 8, 21), 149999)),
        EiDepositMatch.notFound,
      );
    });

    test('without a pay date, the deposit is looked for after the period', () {
      final noPayDate = stub(
        's1',
        d(2026, 8, 3),
        d(2026, 8, 16),
        80,
        net: 150000,
      );
      expect(
        verify([noPayDate], [deposit('t', d(2026, 8, 21), 150000)])
            .checkFor('s1')!
            .match,
        EiDepositMatch.matched,
      );
      expect(
        verify([noPayDate], [deposit('t', d(2026, 8, 10), 150000)])
            .checkFor('s1')!
            .match,
        EiDepositMatch.notFound,
      );
    });

    test('one deposit accounts for one stub only', () {
      final result = verify(
        [
          stub('s1', d(2026, 8, 3), d(2026, 8, 16), 80,
              payDate: d(2026, 8, 21), net: 150000),
          stub('s2', d(2026, 8, 17), d(2026, 8, 30), 80,
              payDate: d(2026, 8, 23), net: 150000),
        ],
        [deposit('t', d(2026, 8, 22), 150000)],
      );
      expect(
        result.checks.where((c) => c.match == EiDepositMatch.matched),
        hasLength(1),
      );
    });

    test('money that is not pay into the account never verifies a stub', () {
      final purchase = AppTransaction(
        id: 'spend',
        eventType: TransactionEventType.purchase,
        amountCents: 150000,
        currency: 'CAD',
        occurredAt: DateTime(2026, 8, 21, 12),
        category: SpendCategory.other,
        source: TransactionSource.statement,
        merchant: 'Furniture store',
      );
      expect(
        verify([august()], [purchase]).checkFor('s1')!.match,
        EiDepositMatch.notFound,
      );
    });
  });

  test('hours are attributed to the evidence behind them, and a deposit with '
      'no stub is surfaced', () {
    final result = verify(
      [
        stub('s1', d(2026, 8, 3), d(2026, 8, 16), 80,
            payDate: d(2026, 8, 21), net: 250000),
        stub('s2', d(2026, 8, 17), d(2026, 8, 30), 80,
            payDate: d(2026, 9, 4), net: 250000),
        EiHoursRecord(
          id: 'w',
          jobId: 'a',
          periodStart: d(2026, 8, 31),
          periodEnd: d(2026, 9, 6),
          hoursWorked: 40,
        ),
      ],
      [
        deposit('t1', d(2026, 8, 21), 250000),
        // Pay arrived, but not for the amount typed from the second stub.
        deposit('t2', d(2026, 9, 4), 249999),
      ],
    );

    expect(result.hoursFor(EiEvidence.verified), closeTo(80, 1e-9));
    expect(result.hoursFor(EiEvidence.payStub), closeTo(80, 1e-9));
    expect(result.hoursFor(EiEvidence.entered), closeTo(40, 1e-9));
    // Monday to Friday, September 7 to 11, from the usual 40 hours.
    expect(result.hoursFor(EiEvidence.estimated), closeTo(40, 1e-9));
    expect(result.totalHours, closeTo(240, 1e-9));
    expect(result.documentedFraction, closeTo(160 / 240, 1e-9));

    expect(result.checkFor('s2')!.match, EiDepositMatch.notFound);
    expect(result.unmatchedDeposits.map((u) => u.deposit.id), ['t2']);
  });

  group('saved pay stubs', () {
    test('details survive saving, and older entries without them still load',
        () {
      final data = EiTrackerData(jobs: [job], records: [august()]);
      final restored = EiTrackerData.decode(data.encode());
      final details = restored.records.single.payStub!;
      expect(details.payDate, d(2026, 8, 21));
      expect(details.calculatedNetCents, 150000);
      expect(details.eiPremiumCents, 3260);

      final json = data.toJson();
      final record = (json['records']! as List).single as Map;
      record
        ..remove('pay_stub')
        ..remove('overtime_hours');
      final older = EiTrackerData.fromJson(json).records.single;
      expect(older.payStub, isNull);
      expect(older.overtimeHours, 0);
    });

    test('a negative amount is rejected', () {
      final json = EiTrackerData(jobs: [job], records: [august()]).toJson();
      final record = (json['records']! as List).single as Map;
      (record['pay_stub'] as Map)['net_pay_cents'] = -1;
      expect(() => EiTrackerData.fromJson(json), throwsFormatException);
    });

    test('overtime counts as insurable hours', () {
      final record = EiHoursRecord(
        id: 'o',
        jobId: 'a',
        periodStart: d(2026, 8, 3),
        periodEnd: d(2026, 8, 16),
        hoursWorked: 70,
        overtimeHours: 6,
        vacationHours: 4,
      );
      expect(record.insurableHours(EiConfig.rules), 80);
    });
  });
}
