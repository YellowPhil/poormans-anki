class Config {
  const Config({
    required this.port,
    required this.databaseUrl,
    required this.userHeader,
    required this.webRoot,
    required this.corsOrigin,
    required this.maxBodyBytes,
  });

  /// `DATABASE_URL=memory` selects the in-process store (development only).
  factory Config.fromEnv(Map<String, String> env) => Config(
    port: int.parse(env['PORT'] ?? '8080'),
    databaseUrl: env['DATABASE_URL'] ?? 'memory',
    userHeader: (env['USER_HEADER'] ?? 'Remote-Email').toLowerCase(),
    webRoot: env['WEB_ROOT'],
    corsOrigin: env['CORS_ORIGIN'],
    maxBodyBytes: int.parse(env['MAX_BODY_BYTES'] ?? '${32 * 1024 * 1024}'),
  );

  final int port;
  final String databaseUrl;
  final String userHeader;
  final String? webRoot;
  final String? corsOrigin;
  final int maxBodyBytes;
}
