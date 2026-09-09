import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_static/shelf_static.dart';

import 'config.dart';
import 'sync_store.dart';

final _log = Logger('api');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// `/healthz` is public; `/api/*` requires the identity header, which must be
/// set by a trusted proxy that strips any client-supplied value.
Handler buildHandler(SyncStore store, Config config) {
  final api = Router()
    ..get('/v1/me', (Request r) => _json({'email': _user(r)}))
    ..get('/v1/sync', (Request r) async {
      final since = r.url.queryParameters['since'];
      final request = SyncRequest(
        since: since == null ? null : DateTime.parse(since).toUtc(),
      );
      return _json((await store.sync(_user(r), request)).toJson());
    })
    ..post('/v1/sync', (Request r) async {
      final body = await _readJson(r, config.maxBodyBytes);
      final request = SyncRequest.fromJson(body);
      return _json((await store.sync(_user(r), request)).toJson());
    });

  final root = Router()
    ..get('/healthz', (Request r) async {
      final ok = await store.healthy();
      return _json({
        'status': ok ? 'ok' : 'degraded',
        'database': ok,
      }, ok ? 200 : 503);
    })
    ..mount('/api/', _requireUser(config.userHeader)(api.call));

  Handler handler = root.call;
  final webRoot = config.webRoot;
  if (webRoot != null) {
    final static = createStaticHandler(webRoot, defaultDocument: 'index.html');
    final index = createStaticHandler(webRoot, defaultDocument: 'index.html');
    handler = Cascade()
        .add(root.call)
        .add(static)
        .add((r) => index(r.change(path: r.url.path)))
        .handler;
  }
  return const Pipeline()
      .addMiddleware(_logging())
      .addMiddleware(_errors())
      .addMiddleware(_cors(config.corsOrigin))
      .addHandler(handler);
}

String _user(Request r) => r.context['user'] as String;

Middleware _requireUser(String header) =>
    (inner) => (request) {
      final raw = request.headers[header]?.trim().toLowerCase();
      if (raw == null || raw.isEmpty) {
        return _json({'error': 'missing $header header'}, 401);
      }
      if (!_email.hasMatch(raw)) {
        return _json({'error': 'invalid $header header'}, 401);
      }
      return inner(request.change(context: {'user': raw}));
    };

Middleware _errors() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on _BadRequest catch (e) {
        return _json({'error': e.message}, e.status);
      } on FormatException catch (e) {
        return _json({'error': 'malformed request: ${e.message}'}, 400);
      } on TypeError catch (e) {
        return _json({'error': 'malformed request: $e'}, 400);
      } on Object catch (e, st) {
        _log.severe('unhandled', e, st);
        return _json({'error': 'internal error'}, 500);
      }
    };

Middleware _logging() =>
    (inner) => (request) async {
      final started = DateTime.now();
      final response = await inner(request);
      final ms = DateTime.now().difference(started).inMilliseconds;
      _log.info(
        '${request.method} /${request.url.path} ${response.statusCode} ${ms}ms',
      );
      return response;
    };

Middleware _cors(String? origin) {
  if (origin == null) return (inner) => inner;
  final headers = {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Remote-Email',
    'Vary': 'Origin',
  };
  return (inner) => (request) async {
    if (request.method == 'OPTIONS') return Response(204, headers: headers);
    final response = await inner(request);
    return response.change(headers: headers);
  };
}

class _BadRequest implements Exception {
  const _BadRequest(this.message, [this.status = 400]);

  final String message;
  final int status;
}

Future<Map<String, dynamic>> _readJson(Request r, int maxBytes) async {
  final declared = r.contentLength;
  if (declared != null && declared > maxBytes) {
    throw const _BadRequest('request body too large', 413);
  }
  final bytes = <int>[];
  await for (final chunk in r.read()) {
    bytes.addAll(chunk);
    if (bytes.length > maxBytes) {
      throw const _BadRequest('request body too large', 413);
    }
  }
  final decoded = jsonDecode(utf8.decode(bytes));
  if (decoded is! Map<String, dynamic>) {
    throw const _BadRequest('request body must be a JSON object');
  }
  return decoded;
}

Response _json(Object body, [int status = 200]) => Response(
  status,
  body: jsonEncode(body),
  headers: {'content-type': 'application/json; charset=utf-8'},
);
