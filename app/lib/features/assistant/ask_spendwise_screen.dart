import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../services/financial_query_engine.dart';
import '../../state/financial_providers.dart';
import '../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/insight_widgets.dart';

class AskSpendWiseScreen extends ConsumerStatefulWidget {
  const AskSpendWiseScreen({super.key});

  @override
  ConsumerState<AskSpendWiseScreen> createState() => _AskSpendWiseScreenState();
}

class _AskSpendWiseScreenState extends ConsumerState<AskSpendWiseScreen> {
  final _controller = TextEditingController();
  final _engine = const FinancialQueryEngine();
  final List<_Exchange> _history = <_Exchange>[];

  static const _suggestions = <String>[
    'How much did I spend this month?',
    'What are my top merchants?',
    'How much did I spend on groceries?',
    'Show my biggest spending month',
    'How much did my investment rules capture?',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ask(String question) {
    final text = question.trim();
    if (text.isEmpty) return;

    final transactions = ref.read(transactionsProvider).value ?? const [];
    final rules = ref.read(financialRulesProvider).value ?? const [];
    final currency =
        ref.read(preferencesProvider).value?.currency ?? 'CAD';
    final answer = _engine.answer(
      text,
      transactions: transactions,
      rules: rules,
      currency: currency,
    );

    setState(() {
      _history.add(_Exchange(question: text, answer: answer));
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transactions = ref.watch(transactionsProvider);
    final rules = ref.watch(financialRulesProvider);
    final loading =
        (transactions.isLoading && !transactions.hasValue) ||
        (rules.isLoading && !rules.hasValue);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ask SpendWise'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Financial Memory rules',
            onPressed: () => context.push(Routes.financialRules),
            icon: const Icon(Icons.psychology_alt_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: <Widget>[
                SectionCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.auto_awesome_outlined,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Private financial analysis',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Answers are calculated from transactions and Financial Memory rules already stored in SpendWise. Nothing is sent to an external AI service.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (transactions.hasError || rules.hasError)
                  InsightNote(
                    title: 'Your financial data could not be loaded',
                    message: 'Return after your transactions and rules are available.',
                    icon: Icons.cloud_off_outlined,
                  )
                else if (_history.isEmpty) ...<Widget>[
                  Text(
                    'Try asking',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final suggestion in _suggestions)
                        ActionChip(
                          avatar: const Icon(Icons.north_east_rounded, size: 16),
                          label: Text(suggestion),
                          onPressed: () => _ask(suggestion),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    onTap: () => context.push(Routes.financialRules),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          Icons.psychology_alt_outlined,
                          color: AppTheme.warning,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                'Teach SpendWise your household rules',
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'For example: Wealthsimple → investment, employer name → income, spouse transfer → internal transfer.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ] else
                  for (final exchange in _history) ...<Widget>[
                    _QuestionBubble(text: exchange.question),
                    const SizedBox(height: 8),
                    _AnswerCard(
                      answer: exchange.answer,
                      onFollowUp: _ask,
                    ),
                    const SizedBox(height: 18),
                  ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !loading,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _ask,
                      decoration: const InputDecoration(
                        hintText: 'Ask about your spending…',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Ask',
                    onPressed: loading ? null : () => _ask(_controller.text),
                    icon: const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionBubble extends StatelessWidget {
  const _QuestionBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          borderRadius: BorderRadius.circular(18).copyWith(
            bottomRight: const Radius.circular(5),
          ),
        ),
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, required this.onFollowUp});
  final FinancialAnswer answer;
  final ValueChanged<String> onFollowUp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome_rounded,
                size: 19,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(answer.title, style: theme.textTheme.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            answer.body,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
          if (answer.metrics.isNotEmpty) ...<Widget>[
            const Divider(height: 28),
            for (final metric in answer.metrics)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        metric.label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      metric.amountCents != null
                          ? Fmt.money(
                              metric.amountCents!,
                              currency: metric.currency ?? 'CAD',
                            )
                          : metric.textValue ?? '—',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.labelLarge,
                    ),
                  ],
                ),
              ),
          ],
          if (answer.followUps.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: <Widget>[
                for (final followUp in answer.followUps.take(3))
                  ActionChip(
                    label: Text(followUp),
                    onPressed: () => onFollowUp(followUp),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Exchange {
  const _Exchange({required this.question, required this.answer});
  final String question;
  final FinancialAnswer answer;
}
