import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';

/// Shown while preferences load and the router decides where to send the user.
///
/// It also reports a genuinely stuck state: if preferences fail to load, the
/// user gets an error and a retry rather than an indefinite spinner.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(preferencesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[AppTheme.brand, AppTheme.brandBright],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.savings_outlined,
                  size: 44,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text('SpendWise', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'Spending tracked automatically',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 40),
              preferences.when(
                loading: () => const CircularProgressIndicator(),
                error: (error, _) => Column(
                  children: <Widget>[
                    Icon(Icons.error_outline_rounded,
                        color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load your settings.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => ref.invalidate(preferencesProvider),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
                data: (_) => const CircularProgressIndicator(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
