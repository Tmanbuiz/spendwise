import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/diagnostics.dart';
import '../../core/formatters.dart';
import '../../core/theme/app_theme.dart';
import '../../services/capture_controller.dart';
import '../../widgets/common.dart';

/// Shows what actually went wrong.
///
/// Exists because a sideloaded release build has no crash reporter and usually
/// no cable attached, so the screen is the only channel a diagnosis can travel
/// through. Everything here is copyable for exactly that reason.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  @override
  void initState() {
    super.initState();
    Diagnostics.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    Diagnostics.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  String _asText() {
    return Diagnostics.instance.errors
        .map((e) => <String>[
              '${Fmt.shortDate(e.at)} ${Fmt.time(e.at)}'
                  '${e.context == null ? '' : '  [${e.context}]'}',
              e.error.toString(),
              if (e.stack != null) e.stack.toString(),
            ].join('\n'))
        .join('\n\n---\n\n');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errors = Diagnostics.instance.errors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: <Widget>[
          if (errors.isNotEmpty) ...<Widget>[
            IconButton(
              tooltip: 'Copy all',
              icon: const Icon(Icons.copy_all_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _asText()));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
            ),
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: Diagnostics.instance.clear,
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: <Widget>[
          const SectionHeader(title: 'Recent captures'),
          const _RecentCaptures(),
          const SizedBox(height: 20),
          const SectionHeader(title: 'Errors'),
          if (errors.isEmpty)
            const SectionCard(
              child: EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'No errors recorded',
                message: 'If something is not working, come back here right '
                    'after trying it — the failure will be listed.',
              ),
            )
          else
            ...errors.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              entry.context ?? 'error',
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                          Text(
                            Fmt.time(entry.at),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        entry.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          height: 1.45,
                        ),
                      ),
                      if (entry.stack != null) ...<Widget>[
                        const SizedBox(height: 8),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            'Stack trace',
                            style: theme.textTheme.labelMedium,
                          ),
                          children: <Widget>[
                            SelectableText(
                              entry.stack.toString(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ))),
        ],
      ),
    );
  }
}

/// The last few notifications the capture pipeline handled, and what it did
/// with each.
///
/// This is the missing link when capture "does nothing": the counters prove a
/// notification arrived and the dashboard proves nothing was recorded, but
/// neither says which step discarded it.
class _RecentCaptures extends ConsumerStatefulWidget {
  const _RecentCaptures();

  @override
  ConsumerState<_RecentCaptures> createState() => _RecentCapturesState();
}

class _RecentCapturesState extends ConsumerState<_RecentCaptures> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = ref.read(captureControllerProvider).recentResults;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  results.isEmpty
                      ? 'Nothing handled yet'
                      : '${results.length} handled',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  await ref
                      .read(captureControllerProvider)
                      .drainPending(rescanFirst: true);
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Re-scan'),
              ),
            ],
          ),
          if (results.isEmpty)
            Text(
              'Tap Re-scan to read the notifications currently on your phone.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...results.map((result) {
              final stored = result.wasStored;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(
                      stored
                          ? Icons.check_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 16,
                      color: stored
                          ? AppTheme.positive
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            result.status.name,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (result.note != null)
                            SelectableText(
                              result.note!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
