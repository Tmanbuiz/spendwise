import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// One captured failure.
class RecordedError {
  RecordedError(Object value, StackTrace? trace, {this.context})
      : error = value.runtimeType.toString(), stack = null, at = DateTime.now();

  final Object error;
  final StackTrace? stack;
  final String? context;
  final DateTime at;

  String get summary {
    final text = error.toString();
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}

/// Collects errors so they can be shown to the user.
///
/// Release builds deliberately swallow exceptions and render a blank grey box,
/// which is why a broken app looks like an app where "nothing works" rather
/// than one reporting a specific fault. On a sideloaded build there is no crash
/// reporter and often no cable attached, so the only place a diagnosis can
/// surface is the screen itself.
class Diagnostics extends ChangeNotifier {
  Diagnostics._();

  static final Diagnostics instance = Diagnostics._();

  final List<RecordedError> _errors = <RecordedError>[];

  List<RecordedError> get errors => List.unmodifiable(_errors);

  bool get hasErrors => _errors.isNotEmpty;

  RecordedError? get latest => _errors.isEmpty ? null : _errors.first;

  void record(Object error, StackTrace? stack, {String? context}) {
    _errors.insert(0, RecordedError(error, stack, context: context));
    // Bounded: a repeating failure must not grow without limit.
    if (_errors.length > 30) _errors.removeLast();
    debugPrint('SpendWise error: ${error.runtimeType}');
    notifyListeners();
  }

  void clear() {
    _errors.clear();
    notifyListeners();
  }

  /// Installs global handlers. Call before `runApp`.
  static void install() {
    FlutterError.onError = (details) {
      instance.record(
        details.exception,
        details.stack,
        context: details.context?.toString(),
      );
      // Do not forward exception text: platform errors can contain financial rows.
    };

    // Errors escaping the widget tree — a failed provider build, a rejected
    // future — would otherwise vanish entirely in release.
    PlatformDispatcher.instance.onError = (error, stack) {
      instance.record(error, stack, context: 'uncaught');
      return true;
    };

    // Replaces the blank grey box release mode shows for a build failure with
    // something that names the fault.
    ErrorWidget.builder = (details) {
      instance.record(details.exception, details.stack, context: 'widget');
      return _InlineError(details: details);
    };
  }
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFDF2F2),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Row(
                children: <Widget>[
                  Icon(Icons.error_outline_rounded,
                      color: Color(0xFFB91C1C), size: 18),
                  SizedBox(width: 8),
                  Text(
                    'This part failed to draw',
                    style: TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Error code: ${details.exception.runtimeType}',
                style: const TextStyle(
                  color: Color(0xFF7F1D1D),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Settings → Diagnostics has the full details.',
                style: TextStyle(color: Color(0xFF7F1D1D), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
