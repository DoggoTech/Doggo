/// Claves de Supabase, inyectadas al compilar:
/// `--dart-define-from-file=env.json` en local y `--dart-define=...` (desde
/// los secretos de GitHub) al publicar. Sin ellas la app corre en modo demo.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// ¿Hay un backend real configurado?
const supabaseConfigured = supabaseUrl != '' && supabaseAnonKey != '';
