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
  Future<SyncResponse> sync(SyncRequest request);
}

class HttpSyncClient implements SyncClient {
  HttpSyncClient(this._http, String serverUrl, {this.email})
    : _endpoint = Uri.parse(serverUrl.endsWith('/') ? serverUrl : '$serverUrl/')
          .resolve('api/v1/sync');

  final http.Client _http;
  final Uri _endpoint;
  final String? email;

  @override
  Future<SyncResponse> sync(SyncRequest request) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            _endpoint,
            headers: {
              'content-type': 'application/json',
              if (email case final e? when e.trim().isNotEmpty)
                'Remote-Email': e.trim(),
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      throw SyncException('Cannot reach $_endpoint: $e');
    }
    if (response.statusCode != 200) {
      throw SyncException(
        'Server returned ${response.statusCode}: ${_errorOf(response.body)}',
      );
    }
    try {
      return SyncResponse.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on Object catch (e) {
      throw SyncException('Unreadable server response: $e');
    }
  }

  static String _errorOf(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is String) {
        return decoded['error'] as String;
      }
    } on FormatException {
      return body.length > 200 ? '${body.substring(0, 200)}…' : body;
    }
    return body;
  }
}
