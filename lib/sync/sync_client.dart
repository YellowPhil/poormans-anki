import 'dart:convert';

import 'package:anki_core/anki_core.dart';
import 'package:http/http.dart' as http;

class SyncException implements Exception {
  const SyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SyncClient {
  /// Throws [CursorExpired] when the server answers 410.
  Future<SyncPull> sync(SyncPush push);

  Future<CollectionSnapshot> collection();
}

class HttpSyncClient implements SyncClient {
  HttpSyncClient(this._http, String serverUrl, {this.email})
    : _base = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/');

  final http.Client _http;
  final Uri _base;
  final String? email;

  Uri get _syncUri => _base.resolve('api/v2/sync');

  Uri get _collectionUri => _base.resolve('api/v2/collection');

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (email case final e? when e.trim().isNotEmpty) 'Remote-Email': e.trim(),
  };

  @override
  Future<SyncPull> sync(SyncPush push) async {
    final json = await _send(
      _syncUri,
      () => _http.post(
        _syncUri,
        headers: _headers,
        body: jsonEncode(push.toJson()),
      ),
    );
    return _parse(() => SyncPull.fromJson(json));
  }

  @override
  Future<CollectionSnapshot> collection() async {
    final json = await _send(
      _collectionUri,
      () => _http.get(_collectionUri, headers: _headers),
    );
    return _parse(() => CollectionSnapshot.fromJson(json));
  }

  Future<Map<String, dynamic>> _send(
    Uri uri,
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request().timeout(const Duration(seconds: 60));
    } on Object catch (e) {
      throw SyncException('Cannot reach $uri: $e');
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw SyncException(
        'Server returned ${response.statusCode}: ${_truncate(response.body)}',
      );
    }
    if (response.statusCode == 410 && body is Map && body['floor'] is int) {
      throw CursorExpired(body['floor'] as int);
    }
    if (response.statusCode != 200 || body is! Map<String, dynamic>) {
      final error = body is Map && body['error'] is String
          ? body['error'] as String
          : _truncate(response.body);
      throw SyncException('Server returned ${response.statusCode}: $error');
    }
    return body;
  }

  static T _parse<T>(T Function() parse) {
    try {
      return parse();
    } on Object catch (e) {
      throw SyncException('Unreadable server response: $e');
    }
  }

  static String _truncate(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;
}
