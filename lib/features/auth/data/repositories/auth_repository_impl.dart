import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Stream<AppUser?> watchAuthUser() {
    return _remote.watchAuthUser();
  }

  @override
  Future<AppUser> signUp({
    required String username,
    required String password,
    required String displayName,
    String? bio,
    String? phoneNumber,
  }) {
    return _remote.signUp(
      username: username,
      password: password,
      displayName: displayName,
      bio: bio,
      phoneNumber: phoneNumber,
    );
  }

  @override
  Future<AppUser> login({
    required String username,
    required String password,
  }) {
    return _remote.login(username: username, password: password);
  }

  @override
  Future<void> signOut() {
    return _remote.signOut();
  }

  @override
  Future<void> setPresence({required String userId, required bool isOnline}) {
    return _remote.setPresence(userId: userId, isOnline: isOnline);
  }

  @override
  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? phoneNumber,
    String? avatarUrl,
    String? avatarBase64,
    String? avatarMimeType,
    String? avatarFileName,
    bool? canReceiveMessages,
  }) {
    return _remote.updateProfile(
      displayName: displayName,
      bio: bio,
      phoneNumber: phoneNumber,
      avatarUrl: avatarUrl,
      avatarBase64: avatarBase64,
      avatarMimeType: avatarMimeType,
      avatarFileName: avatarFileName,
      canReceiveMessages: canReceiveMessages,
    );
  }

  @override
  Future<AppUser> setUserVerification({
    required String username,
    required bool isVerified,
  }) {
    return _remote.setUserVerification(
      username: username,
      isVerified: isVerified,
    );
  }
}
