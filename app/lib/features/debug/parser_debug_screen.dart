import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendwise_parser/spendwise_parser.dart';

import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';

/// Paste a bank notification and see exactly what SpendWise makes of it.
///
/// Nothing here writes to storage: the point is to test parsing without
/// waiting for a real transaction, and without polluting the ledger. The
/// result shown is the same object the capture pipeline would store.
class ParserDebugScreen extends ConsumerStatefulWidget {
  const ParserDebugScreen({super.key});

  @override
  ConsumerState<ParserDebugScreen> createState() => _ParserDebugScreenState();
}

class _ParserDebugScreenState extends ConsumerState<ParserDebugScreen> {
  final _input = TextEditingController();
  ParsedTransaction? _result;

  /// Ready-made samples covering each event type, so the screen is useful
  /// before the user has any notification text to hand.
  static const List<(String, String)> _samples = <(String, String)>[
    (
      'Purchase',
      r'A transaction of $45.67 was made on your CIBC Dividend Visa Infinite '
          'card ending in 1234 at TIM HORTONS #123 on Sep 3, 2026 at 8:14 AM.'
    ),
    (
      'Refund',
      r'A refund of $45.67 was credited to your CIBC Dividend Visa card '
          'ending in 1234 from BEST BUY.'
    ),
    (
      'Card payment',
      r'Thank you for your payment of $500.00 to your CIBC Visa ending '
          'in 1234.'
    ),
    (
      'Transfer',
      r'You sent an INTERAC e-Transfer of $50.00 to John Smith from your '
          'CIBC Smart Account ending in 3344.'
    ),
    (
      'Declined',
      r'A transaction of $89.99 at AMAZON.CA was declined on your CIBC '
          'card ending in 5678.'
    ),
    (
      'Bill payment',
      r'A bill payment of $142.08 to TORONTO HYDRO was made from your '
          'CIBC Smart Account ending in 3344.'
    ),
    (
      'Not a transaction',
      r'Your CIBC Dividend Visa statement is ready. Your statement balance '
          r'is $1,204.55.'
    ),
  ];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _parse() {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() => _result = null);
      return;
    }
    setState(() => _result = parseCibcText(text));
  }

  void _useSample(String text) {
    _input.text = text;
    _parse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categorizer = ref.watch(categorizerProvider);
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('Parser test')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          Text(
            'Paste a bank notification to see how it would be read. Nothing '
            'is saved.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            maxLines: 5,
            minLines: 3,
            onChanged: (_) => _parse(),
            decoration: const InputDecoration(
              hintText: 'A transaction of \$45.67 was made at ...',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final sample in _samples)
                ActionChip(
                  label: Text(sample.$1),
                  onPressed: () => _useSample(sample.$2),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (result == null)
            const SectionCard(
              child: EmptyState(
                icon: Icons.science_outlined,
                title: 'Nothing parsed yet',
                message: 'Paste a notification or tap one of the samples.',
              ),
            )
          else
            _ResultView(result: result, categorizer: categorizer),
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({required this.result, required this.categorizer});

  final ParsedTransaction result;
  final Categorizer categorizer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = categorizer.categoryFor(result.merchantNormalized);
    final counts = result.countsAsSpending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    AppTheme.eventIcon(result.eventType),
                    color: counts ? AppTheme.negative : AppTheme.positive,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    result.eventType.name.toUpperCase(),
                    style: theme.textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (counts ? AppTheme.negative : AppTheme.positive)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      counts ? 'Counts as spending' : 'Not counted',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            counts ? AppTheme.negative : AppTheme.positive,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 28),
              _Field(
                label: 'Amount',
                value: result.amount == null
                    ? 'not found'
                    : Fmt.money(
                        result.amount!.cents,
                        currency: result.amount!.currency,
                      ),
                missing: result.amount == null,
              ),
              _Field(
                label: 'Currency',
                value: result.amount?.currency ?? 'not found',
                missing: result.amount == null,
              ),
              _Field(
                label: 'Merchant',
                value: result.merchantRaw ?? 'not found',
                missing: result.merchantRaw == null,
              ),
              _Field(
                label: 'Normalised',
                value: result.merchantNormalized ?? '—',
                missing: result.merchantNormalized == null,
              ),
              _Field(
                label: 'Category',
                value: category.displayName,
              ),
              _Field(
                label: 'Card',
                value: <String?>[
                  result.accountLabel,
                  if (result.accountLast4 != null) '••${result.accountLast4}',
                ].whereType<String>().join(' ').trim().isEmpty
                    ? 'not found'
                    : <String?>[
                        result.accountLabel,
                        if (result.accountLast4 != null)
                          '••${result.accountLast4}',
                      ].whereType<String>().join(' '),
                missing:
                    result.accountLabel == null && result.accountLast4 == null,
              ),
              _Field(
                label: 'When',
                value: '${Fmt.shortDate(result.occurredAt)} at '
                    '${Fmt.time(result.occurredAt)}'
                    '${result.occurredAtIsExact ? "" : "  (from delivery time)"}',
              ),
              _Field(
                label: 'Confidence',
                value: Fmt.percent(result.confidence),
              ),
              _Field(label: 'Fingerprint', value: result.fingerprint),
            ],
          ),
        ),
        if (result.gaps.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.error_outline_rounded,
                        size: 18, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Text('What could not be read',
                        style: theme.textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 10),
                for (final gap in result.gaps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${_gapLabel(gap)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.shield_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('Retention', style: theme.textTheme.labelLarge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                result.rawRetention == RawRetention.discard
                    ? 'The parse is complete, so the original notification '
                        'text is discarded once the transaction is written.'
                    : 'The parse is incomplete, so a redacted copy is kept for '
                        '${RawRetention.reviewTtl.inDays} days to improve '
                        'coverage. Every digit is masked.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
              if (result.redactedRaw != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    result.redactedRaw!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String _gapLabel(ParseGap gap) {
  switch (gap) {
    case ParseGap.noAmount:
      return 'No amount could be found';
    case ParseGap.noMerchant:
      return 'No merchant could be found';
    case ParseGap.noAccount:
      return 'No card or account was named';
    case ParseGap.noTimestamp:
      return 'No date in the text — delivery time used instead';
    case ParseGap.ambiguousType:
      return 'The kind of transaction was ambiguous';
    case ParseGap.notATransaction:
      return 'This is not a transaction notification';
    case ParseGap.emptyMessage:
      return 'The notification was empty';
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.missing = false,
  });

  final String label;
  final String value;
  final bool missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 104,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: missing ? theme.colorScheme.onSurfaceVariant : null,
                fontStyle: missing ? FontStyle.italic : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
