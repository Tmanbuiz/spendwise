import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
import 'core/diagnostics.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'state/providers.dart';

Future<void> main() async {
  // Installed before anything else so a failure during startup is captured
  // rather than lost.
  Diagnostics.install();

  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Config first, then storage: the data layer's choice between Supabase
      // and the local store depends on whether .env carries real credentials.
      //
      // Both are guarded because neither is worth failing to launch over. A
      // startup exception here would leave the user with an app that opens to
      // nothing and explains nothing — the failure mode hardest to diagnose
      // from the outside.
      try {
        await Env.load();
      } on Object catch (error, stack) {
        Diagnostics.instance.record(error, stack, context: 'Env.load');
      }

      var started = false;
      try {
        await bootstrapDataLayer();
        started = true;
      } on Object catch (error, stack) {
        Diagnostics.instance.record(error, stack, context: 'bootstrapDataLayer');
      }

      if (started) {
        runApp(const ProviderScope(child: SpendWiseApp()));
      } else {
        // Storage is the one dependency the app genuinely cannot run without,
        // so say so plainly instead of showing an empty shell.
        runApp(const _StartupFailureApp());
      }
    },
    (error, stack) =>
        Diagnostics.instance.record(error, stack, context: 'zone'),
  );
}

class SpendWiseApp extends ConsumerWidget {
  const SpendWiseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'SpendWise',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Shown when storage could not be opened, so the app cannot function.
class _StartupFailureApp extends StatelessWidget {
  const _StartupFailureApp();

  @override
  Widget build(BuildContext context) {
    final error = Diagnostics.instance.latest;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.error_outline_rounded, size: 40),
                const SizedBox(height: 16),
                const Text(
                  'SpendWise could not open its storage',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  error?.summary ?? 'No further detail was captured.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
