import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Runtime configuration, loaded from a git-ignored `.env` file.
///
/// Only client-safe values live here. The Supabase service-role key is never
/// read by the app — it bypasses Row Level Security and belongs server-side.
abstract final class Env {
  static bool _loaded = false;

  /// Loads `.env`. Never throws: a missing or malformed file leaves the app
  /// unconfigured rather than crashing on launch, so the user sees the setup
  /// screen instead of a blank crash.
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
      _loaded = true;
    } on Object {
      _loaded = false;
    }
  }

  static String _get(String key, {String fallback = ''}) {
    if (!_loaded) return fallback;
    return dotenv.env[key]?.trim() ?? fallback;
  }

  static String get supabaseUrl => _get('SUPABASE_URL');

  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');

  /// True when both Supabase values are present and are not the placeholders
  /// shipped in `.env.example`.
  static bool get isConfigured {
    final url = supabaseUrl;
    final key = supabaseAnonKey;
    if (url.isEmpty || key.isEmpty) return false;
    if (url.contains('your-project-ref')) return false;
    if (key.contains('your-anon')) return false;
    return url.startsWith('http');
  }

  /// Currency assumed when a bank alert omits a currency code.
  static String get defaultCurrency {
    final value = _get('DEFAULT_CURRENCY', fallback: 'CAD');
    return value.isEmpty ? 'CAD' : value.toUpperCase();
  }

  /// How close together two identical alerts must be to count as one event.
  static Duration get duplicateWindow {
    final minutes = int.tryParse(_get('DUPLICATE_WINDOW_MINUTES')) ?? 10;
    return Duration(minutes: minutes.clamp(1, 240));
  }

  /// Whether bank-account linking through an aggregator is available.
  ///
  /// Requires a Supabase project too, because the aggregator's secret lives in
  /// an Edge Function — there is nowhere to put it otherwise.
  static bool get aggregatorEnabled {
    if (!isConfigured) return false;
    return _get('AGGREGATOR_ENABLED').toLowerCase() == 'true';
  }

  static String get aggregatorProvider {
    final value = _get('AGGREGATOR_PROVIDER', fallback: 'plaid');
    return value.isEmpty ? 'plaid' : value.toLowerCase();
  }

  /// How long a redacted unparsed sample is kept before it is purged.
  static Duration get rawSampleRetention {
    final days = int.tryParse(_get('RAW_SAMPLE_RETENTION_DAYS')) ?? 30;
    return Duration(days: days.clamp(1, 365));
  }
}
