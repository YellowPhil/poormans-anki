import 'dart:io';

import 'package:anki_server/api.dart';
import 'package:anki_server/config.dart';
import 'package:anki_server/memory_sync_store.dart';
import 'package:anki_server/postgres_sync_store.dart';
import 'package:anki_server/sync_store.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final config = Config.fromEnv(Platform.environment);
  Logger.root
    ..level = Level.LEVELS.firstWhere(
      (l) => l.name == (Platform.environment['LOG_LEVEL'] ?? 'INFO'),
      orElse: () => Level.INFO,
    )
    ..onRecord.listen((r) {
      stdout.writeln(
        '${r.time.toUtc().toIso8601String()} ${r.level.name} ${r.loggerName}: ${r.message}'
        '${r.error == null ? '' : ' ${r.error}'}',
      );
      if (r.stackTrace != null) stdout.writeln(r.stackTrace);
    });
  final log = Logger('server');

  final SyncStore store = config.databaseUrl == 'memory'
      ? MemorySyncStore()
      : await PostgresSyncStore.open(config.databaseUrl);
  log.info(
    'store: ${config.databaseUrl == 'memory' ? 'memory' : 'postgres'}'
    '${config.webRoot == null ? '' : ', serving web from ${config.webRoot}'}',
  );

  final server = await shelf_io.serve(
    buildHandler(store, config),
    InternetAddress.anyIPv4,
    config.port,
    poweredByHeader: null,
  );
  log.info('listening on :${server.port}');

  Future<void> shutdown(ProcessSignal signal) async {
    log.info('received $signal, shutting down');
    await server.close();
    await store.close();
    exit(0);
  }

  ProcessSignal.sigterm.watch().listen(shutdown);
  ProcessSignal.sigint.watch().listen(shutdown);
}
