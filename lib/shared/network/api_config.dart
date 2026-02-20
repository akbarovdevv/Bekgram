import 'package:flutter/foundation.dart';

class ApiConfig {
  static const int _defaultPort =
      int.fromEnvironment('API_PORT', defaultValue: 3000);

  static String get _host {
    const envHost = String.fromEnvironment('API_HOST', defaultValue: '');
    if (envHost.isNotEmpty) {
      return envHost;
    }

    if (kIsWeb) {
      return Uri.base.host;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      // Android emulator -> host machine loopback
      return '10.0.2.2';
    }

    return '127.0.0.1';
  }

  static String get baseUrl => 'http://$_host:$_defaultPort/api';

  static String get socketUrl => 'http://$_host:$_defaultPort';
}
