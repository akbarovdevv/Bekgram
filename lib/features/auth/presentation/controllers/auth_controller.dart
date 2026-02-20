import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/network_providers.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/app_user.dart';
import '../../domain/repositories/auth_repository.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) {
  return AuthRemoteDataSource(
    ref.watch(apiClientProvider),
    ref.watch(sessionStoreProvider),
    ref.watch(socketServiceProvider),
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider));
});

final authUserProvider = StreamProvider<AppUser?>((ref) {
  return ref.watch(authRepositoryProvider).watchAuthUser();
});

final currentUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(authUserProvider).valueOrNull;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<void>>((ref) {
  return AuthController(ref.watch(authRepositoryProvider));
});

class AuthController extends StateNotifier<AsyncValue<void>> {
  AuthController(this._repository) : super(const AsyncData(null));

  final AuthRepository _repository;

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.login(username: username, password: password);
      state = const AsyncData(null);
      return null;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return error.toString();
    }
  }

  Future<String?> signUp({
    required String username,
    required String password,
    required String displayName,
    String? bio,
    String? phoneNumber,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.signUp(
        username: username,
        password: password,
        displayName: displayName,
        bio: bio,
        phoneNumber: phoneNumber,
      );
      state = const AsyncData(null);
      return null;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return error.toString();
    }
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.signOut);
  }

  Future<void> setPresence(
      {required String userId, required bool isOnline}) async {
    try {
      await _repository.setPresence(userId: userId, isOnline: isOnline);
    } catch (_) {
      // Presence should not block UX.
    }
  }

  Future<String?> updateProfile({
    String? displayName,
    String? bio,
    String? phoneNumber,
    String? avatarUrl,
    String? avatarBase64,
    String? avatarMimeType,
    String? avatarFileName,
    bool? canReceiveMessages,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.updateProfile(
        displayName: displayName,
        bio: bio,
        phoneNumber: phoneNumber,
        avatarUrl: avatarUrl,
        avatarBase64: avatarBase64,
        avatarMimeType: avatarMimeType,
        avatarFileName: avatarFileName,
        canReceiveMessages: canReceiveMessages,
      );
      state = const AsyncData(null);
      return null;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return error.toString();
    }
  }

  Future<String?> setUserVerification({
    required String username,
    required bool isVerified,
  }) async {
    state = const AsyncLoading();
    try {
      await _repository.setUserVerification(
        username: username,
        isVerified: isVerified,
      );
      state = const AsyncData(null);
      return null;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return error.toString();
    }
  }
}
