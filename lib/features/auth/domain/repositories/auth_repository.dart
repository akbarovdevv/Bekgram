import '../entities/app_user.dart';

abstract class AuthRepository {
  Stream<AppUser?> watchAuthUser();

  Future<AppUser> signUp({
    required String username,
    required String password,
    required String displayName,
    String? bio,
    String? phoneNumber,
  });

  Future<AppUser> login({
    required String username,
    required String password,
  });

  Future<void> signOut();

  Future<void> setPresence({
    required String userId,
    required bool isOnline,
  });

  Future<AppUser> updateProfile({
    String? displayName,
    String? bio,
    String? phoneNumber,
    String? avatarUrl,
    String? avatarBase64,
    String? avatarMimeType,
    String? avatarFileName,
    bool? canReceiveMessages,
  });

  Future<AppUser> setUserVerification({
    required String username,
    required bool isVerified,
  });
}
