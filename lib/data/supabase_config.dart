/// Supabase bağlantı ayarları.
///
/// Değerler derleme zamanında `--dart-define` ile verilir; kaynak koda gömülmez.
///
/// ```bash
/// flutter build apk   --dart-define=SUPABASE_URL=https://<ref>.supabase.co   \
///                     --dart-define=SUPABASE_PUBLISHABLE_KEY=<sb_publishable_...>
/// flutter build web   --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=...
/// ```
///
/// Burada yalnızca *publishable* (`sb_publishable_…`) anahtar kullanılabilir.
/// `service_role` anahtarı istemciye asla verilmez.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');

  static const String publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Ortam değişkenleri tanımlanmadan derlendiyse uygulama boş bir URL ile
  /// açılmaya çalışmasın; erken ve anlaşılır bir hata verilsin.
  static void ensureConfigured() {
    if (url.isEmpty || publishableKey.isEmpty) {
      throw StateError(
        'Supabase yapılandırması eksik. Derlerken --dart-define=SUPABASE_URL=... '
        've --dart-define=SUPABASE_PUBLISHABLE_KEY=... verilmelidir.',
      );
    }
  }
}
