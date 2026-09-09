import 'package:flutter/foundation.dart';

/// [email] is only for development without the identity proxy: the client
/// then sends it as the `Remote-Email` header itself.
class SyncSettings {
  const SyncSettings({this.serverUrl, this.email});

  factory SyncSettings.fromJson(Map<String, dynamic> json) => SyncSettings(
    serverUrl: json['serverUrl'] as String?,
    email: json['email'] as String?,
  );

  /// On the web the app is served by the sync server, so sync is on by
  /// default against the page origin; native builds start with sync off.
  factory SyncSettings.defaults() =>
      kIsWeb ? SyncSettings(serverUrl: Uri.base.origin) : const SyncSettings();

  final String? serverUrl;
  final String? email;

  bool get enabled => serverUrl != null && serverUrl!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    if (serverUrl != null) 'serverUrl': serverUrl,
    if (email != null) 'email': email,
  };
}
