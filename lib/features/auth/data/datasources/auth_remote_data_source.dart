import '../../../../shared/network/api_client.dart';
import '../../../../shared/network/session_store.dart';
import '../../../../shared/network/socket_service.dart';
import '../models/app_user_model.dart';

class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthRemoteDataSource {
  AuthRemoteDataSource(
      this._apiClient, this._sessionStore, this._socketService);

  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  final SocketService _socketService;

  Stream<AppUserModel?> watchAuthUser() {
    return _sessionStore.watchUser().map((user) {
      final token = _sessionStore.token;
      if (user != null && token != null && token.isNotEmpty) {
        _socketService.connect(token);
      }
      return user;
    });
  }

  Future<AppUserModel> signUp({
    required String username,
    required String password,
    required String displayName,
    String? bio,
    String? phoneNumber,
  }) async {
    _validate(
      usernameLower: _normalizeUsername(username),
      password: password,
      displayName: displayName,
    );

    try {
      final data = await _apiClient.post(
        '/auth/signup',
        authRequired: false,
        body: {
          'username': username,
          'password': password,
          'displayName': displayName,
          'bio': bio,
          'phoneNumber': phoneNumber,
        },
      );

      final map = _asMap(data);
      final token = _readString(map, 'token');
      final userMap = _asMap(map['user']);
      final user = AppUserModel.fromJson(userMap);

      await _sessionStore.saveSession(token: token, user: user);
      _socketService.connect(token);
      _socketService.setPresence(true);

      return user;
    } on ApiException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure('Sign up jarayonida xatolik yuz berdi.');
    }
  }

  Future<AppUserModel> login({
    required String username,
    required String password,
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      throw const AuthFailure('Username va parol kiritilishi shart.');
    }

    try {
      final data = await _apiClient.post(
        '/auth/login',
        authRequired: false,
        body: {
          'username': username,
          'password': password,
        },
      );

      final map = _asMap(data);
      final token = _readString(map, 'token');
      final userMap = _asMap(map['user']);
      final user = AppUserModel.fromJson(userMap);

      await _sessionStore.saveSession(token: token, user: user);
      _socketService.connect(token);
      _socketService.setPresence(true);

      return user;
    } on ApiException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure('Login jarayonida xatolik yuz berdi.');
    }
  }

  Future<void> signOut() async {
    try {
      await _apiClient.post('/auth/logout', body: {});
    } catch (_) {
      // Ignore network/logged out edge cases.
    }

    _socketService.disconnect();
    await _sessionStore.clearSession();
  }

  Future<void> setPresence({
    required String userId,
    required bool isOnline,
  }) async {
    try {
      await _apiClient.post('/auth/presence', body: {'isOnline': isOnline});
      _socketService.setPresence(isOnline);
    } catch (_) {
      // Presence failures should not break user flow.
    }
  }

  Future<AppUserModel> updateProfile({
    String? displayName,
    String? bio,
    String? phoneNumber,
    String? avatarUrl,
    String? avatarBase64,
    String? avatarMimeType,
    String? avatarFileName,
    bool? canReceiveMessages,
  }) async {
    final body = <String, dynamic>{};
    if (displayName != null) body['displayName'] = displayName;
    if (bio != null) body['bio'] = bio;
    if (phoneNumber != null) body['phoneNumber'] = phoneNumber;
    if (avatarUrl != null) body['avatarUrl'] = avatarUrl;
    if (avatarBase64 != null) body['avatarBase64'] = avatarBase64;
    if (avatarMimeType != null) body['avatarMimeType'] = avatarMimeType;
    if (avatarFileName != null) body['avatarFileName'] = avatarFileName;
    if (canReceiveMessages != null) {
      body['canReceiveMessages'] = canReceiveMessages;
    }

    if (body.isEmpty) {
      throw const AuthFailure('Yangilash uchun maydon tanlanmadi.');
    }

    try {
      final data = await _apiClient.put('/auth/me', body: body);
      final map = _asMap(data);
      final userMap = _asMap(map['user']);
      final user = AppUserModel.fromJson(userMap);

      await _sessionStore.updateUser(user);
      return user;
    } on ApiException catch (error) {
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure('Profilni saqlashda xatolik yuz berdi.');
    }
  }

  Future<AppUserModel> setUserVerification({
    required String username,
    required bool isVerified,
  }) async {
    final usernameLower = _normalizeUsername(username);
    final validUsername = RegExp(r'^[a-z0-9_]{4,24}$').hasMatch(usernameLower);
    if (!validUsername) {
      throw const AuthFailure(
          "Username 4-24 ta: a-z, 0-9 yoki _ bo'lishi kerak.");
    }

    try {
      final data = await _apiClient.put(
        '/users/verify',
        body: {
          'username': usernameLower,
          'isVerified': isVerified,
        },
      );
      final map = _asMap(data);
      final userMap = _asMap(map['user']);
      final user = AppUserModel.fromJson(userMap);

      final current = _sessionStore.user;
      if (current?.id == user.id) {
        await _sessionStore.updateUser(user);
      }
      return user;
    } on ApiException catch (error) {
      final message = error.message.toLowerCase();
      if (error.statusCode == 404 && message.contains('route')) {
        throw const AuthFailure(
          "Backend eski versiyada ishlayapti. `cd server && npm run dev` bilan qayta ishga tushiring.",
        );
      }
      throw AuthFailure(error.message);
    } catch (_) {
      throw const AuthFailure(
          'Verification holatini saqlashda xatolik yuz berdi.');
    }
  }

  void _validate({
    required String usernameLower,
    required String password,
    required String displayName,
  }) {
    final validUsername = RegExp(r'^[a-z0-9_]{4,24}$').hasMatch(usernameLower);
    if (!validUsername) {
      throw const AuthFailure(
          "Username 4-24 ta: a-z, 0-9 yoki _ bo'lishi kerak.");
    }

    if (password.length < 6) {
      throw const AuthFailure("Parol kamida 6 ta belgidan iborat bo'lsin.");
    }

    if (displayName.trim().length < 2) {
      throw const AuthFailure("Ism kamida 2 ta belgidan iborat bo'lsin.");
    }
  }

  String _normalizeUsername(String username) {
    return username.trim().toLowerCase().replaceAll(' ', '');
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }

  String _readString(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
    throw const AuthFailure('Server javobida token topilmadi.');
  }
}
