/// Claves de Supabase, inyectadas al compilar:
/// `--dart-define-from-file=env.json` en local y `--dart-define=...` (desde
/// los secretos de GitHub) al publicar. Sin ellas la app corre en modo demo.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// ¿Hay un backend real configurado?
const supabaseConfigured = supabaseUrl != '' && supabaseAnonKey != '';

/// Solicitudes de ejemplo en el panel del cuidador del modo demo. Las pruebas
/// e2e compilan con `--dart-define=DEMO_SAMPLE_BOOKINGS=false`.
const demoSampleBookings = bool.fromEnvironment(
  'DEMO_SAMPLE_BOOKINGS',
  defaultValue: true,
);
