class SupabaseConfig {
  // Inserisci qui URL e anon key del tuo progetto Supabase.
  // Le trovi in: Supabase Dashboard -> Project Settings -> API
  static const String url = 'https://yzdawvvlnulfrpweimyh.supabase.co';
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl6ZGF3dnZsbnVsZnJwd2VpbXloIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODIyMDQ4OTUsImV4cCI6MjA5Nzc4MDg5NX0.4yMPybm5GD57f8vrwwhlPxI_Pms6IgmtOKjoe3M93cs';

  static String get normalizedUrl {
    var value = url.trim();
    if (value.isEmpty) return value;

    // Se viene incollato solo il project ref, convertiamo al dominio Supabase.
    if (!value.contains('.') && !value.contains('://')) {
      value = '$value.supabase.co';
    }

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'https://$value';
    }

    // Evita doppio slash finale nei path generati dal client.
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }

    return value;
  }

  static Uri? get parsedUrl => Uri.tryParse(normalizedUrl);

  static bool get hasValidUrl {
    final uri = parsedUrl;
    return uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.trim().isNotEmpty;
  }

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty && hasValidUrl;
}
