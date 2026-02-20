import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/data/models/app_user_model.dart';

class SessionStore {
  SessionStore();

  static const _tokenKey = 'bekgram_token';
  static const _userKey = 'bekgram_user';

  SharedPreferences? _prefs;
  bool _initialized = false;

  String? _token;
  AppUserModel? _user;

  final StreamController<AppUserModel?> _userController =
      StreamController<AppUserModel?>.broadcast();

  String? get token => _token;

  AppUserModel? get user => _user;

  Stream<AppUserModel?> watchUser() async* {
    await ensureInitialized();
    yield _user;
    yield* _userController.stream;
  }

  Future<void> ensureInitialized() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    _token = _prefs?.getString(_tokenKey);

    final rawUser = _prefs?.getString(_userKey);
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawUser) as Map<String, dynamic>;
        _user = AppUserModel.fromJson(decoded);
      } catch (_) {
        _user = null;
      }
    }

    _initialized = true;
  }

  Future<void> saveSession({
    required String token,
    required AppUserModel user,
  }) async {
    await ensureInitialized();

    _token = token;
    _user = user;

    await _prefs?.setString(_tokenKey, token);
    await _prefs?.setString(_userKey, jsonEncode(user.toJson()));

    _userController.add(_user);
  }

  Future<void> updateUser(AppUserModel user) async {
    await ensureInitialized();

    _user = user;
    await _prefs?.setString(_userKey, jsonEncode(user.toJson()));
    _userController.add(_user);
  }

  Future<void> clearSession() async {
    await ensureInitialized();

    _token = null;
    _user = null;

    await _prefs?.remove(_tokenKey);
    await _prefs?.remove(_userKey);

    _userController.add(null);
  }
}
