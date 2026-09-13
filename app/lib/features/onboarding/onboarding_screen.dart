import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../state/providers.dart';

/// Explains what the app does and what it needs, before asking for anything.
///
/// Notification access is an unusually broad Android permission, so the value
/// exchange is stated up front — and so are the limits — rather than the user
/// being dropped into a system settings page and left to guess.
///
/// Where notifications cannot be read at all, as on iPhone, the introduction
/// describes the app that does exist there and setup ends with it.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const List<_Slide> _iphoneSlides = <_Slide>[
    _Slide(
      icon: Icons.upload_file_outlined,
      title: 'Your statements, sorted for you',
      body: 'Import the PDF or CSV statements your bank lets you download, or '
          'open one from Files or Mail with Open in SpendWise.',
    ),
    _Slide(
      icon: Icons.auto_awesome_outlined,
      title: 'Sorted into categories for you',
      body: 'Groceries, dining, gas, subscriptions and more are recognised '
          'automatically. Correct one once and SpendWise remembers.',
    ),
    _Slide(
      icon: Icons.shield_outlined,
      title: 'Private, and read-only',
      body: 'SpendWise cannot move money and never asks for your banking '
          'password, PIN, CVV or full card number. On iPhone it works from '
          'the statements and pay stubs you add.',
    ),
  ];

  /// Whether this device can capture bank notifications, and so needs banks
  /// chosen and notification access granted.
  bool get _capture => ref.read(notificationAccessProvider).isSupportedPlatform;

  List<_Slide> get _slides => _capture ? _captureSlides : _iphoneSlides;

  /// Ends the introduction. Choosing banks and granting notification access
  /// only mean something where alerts can be captured; everywhere else the
  /// app is ready now.
  Future<void> _finish() async {
    if (_capture) {
      context.go(Routes.bankSelection);
      return;
    }
    await ref.read(preferencesProvider.notifier).completeOnboarding();
    if (mounted) context.go(Routes.dashboard);
  }

  static const List<_Slide> _captureSlides = <_Slide>[
    _Slide(
      icon: Icons.notifications_active_outlined,
      title: 'Spending tracked as it happens',
      body: 'SpendWise reads the purchase alerts your bank already sends to '
          'your phone, and turns them into a running total for the month.',
    ),
    _Slide(
      icon: Icons.auto_awesome_outlined,
      title: 'Sorted into categories for you',
      body: 'Groceries, dining, gas, subscriptions and more are recognised '
          'automatically. Correct one once and SpendWise remembers.',
    ),
    _Slide(
      icon: Icons.shield_outlined,
      title: 'Read-only, and only your banks',
      body: 'SpendWise cannot move money and never asks for your banking '
          'password, PIN, CVV or full card number. It only looks at alerts '
          'from the banks you pick.',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _page == _slides.length - 1;

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _SlideView(_slides[index]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton(
                onPressed: _next,
                child: Text(
                  !_isLast
                      ? 'Next'
                      : _capture
                      ? 'Choose your banks'
                      : 'Get started',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView(this.slide);
  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  AppTheme.brand.withValues(alpha: 0.16),
                  AppTheme.brandBright.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(slide.icon, size: 50, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 36),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
