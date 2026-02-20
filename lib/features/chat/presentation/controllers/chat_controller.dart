import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/network_providers.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../domain/entities/chat_media_attachment.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/verification_request_info.dart';
import '../../domain/repositories/chat_repository.dart';

final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  return ChatRemoteDataSource(
    ref.watch(apiClientProvider),
    ref.watch(sessionStoreProvider),
    ref.watch(socketServiceProvider),
  );
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepositoryImpl(ref.watch(chatRemoteDataSourceProvider));
});

final chatListProvider = StreamProvider.autoDispose<List<ChatThread>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(chatRepositoryProvider).watchChats(user.id);
});

final totalUnreadCountProvider = Provider<int>((ref) {
  final chatsAsync = ref.watch(chatListProvider);
  return chatsAsync.maybeWhen(
    data: (chats) {
      return chats
          .where((chat) => !chat.isSaved)
          .fold<int>(0, (sum, chat) => sum + chat.unreadCount);
    },
    orElse: () => 0,
  );
});

final chatMessagesProvider =
    StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, chatId) {
  return ref.watch(chatRepositoryProvider).watchMessages(chatId);
});

final userByIdProvider =
    StreamProvider.autoDispose.family<AppUser?, String>((ref, userId) {
  return ref.watch(chatRepositoryProvider).watchUser(userId);
});

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');

final searchUsersProvider = StreamProvider.autoDispose<List<AppUser>>((ref) {
  final query = ref.watch(searchQueryProvider);
  final currentUser = ref.watch(currentUserProvider);
  if (currentUser == null || query.trim().isEmpty) {
    return Stream.value(const []);
  }

  return ref.watch(chatRepositoryProvider).searchUsers(
        query: query,
        excludeUserId: currentUser.id,
      );
});

final searchGroupsQueryProvider =
    StateProvider.autoDispose<String>((ref) => '');

final searchPublicGroupsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final query = ref.watch(searchGroupsQueryProvider);
  if (query.trim().isEmpty) return const [];
  return ref.watch(chatRepositoryProvider).searchPublicGroups(query);
});

final chatActionControllerProvider =
    StateNotifierProvider<ChatActionController, AsyncValue<void>>((ref) {
  return ChatActionController(ref.watch(chatRepositoryProvider));
});

class ChatActionController extends StateNotifier<AsyncValue<void>> {
  ChatActionController(this._repository) : super(const AsyncData(null));

  final ChatRepository _repository;

  Future<String> openDirectChat({
    required String currentUserId,
    required AppUser peer,
  }) async {
    state = const AsyncLoading();
    try {
      final chatId = await _repository.getOrCreateDirectChat(
        currentUserId: currentUserId,
        peer: peer,
      );
      state = const AsyncData(null);
      return chatId;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<String> openSavedChat(String userId) async {
    state = const AsyncLoading();
    try {
      final chatId = await _repository.getOrCreateSavedChat(userId);
      state = const AsyncData(null);
      return chatId;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<String> createGroup({
    required String title,
    required String groupUsername,
    required String bio,
    required bool isPublic,
    required List<String> memberUsernames,
  }) async {
    state = const AsyncLoading();
    try {
      final chatId = await _repository.createGroup(
        title: title,
        groupUsername: groupUsername,
        bio: bio,
        isPublic: isPublic,
        memberUsernames: memberUsernames,
      );
      state = const AsyncData(null);
      return chatId;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> addGroupMembers({
    required String chatId,
    required List<String> memberUsernames,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.addGroupMembers(
        chatId: chatId,
        memberUsernames: memberUsernames,
      ),
    );
  }

  Future<String> joinGroup(String chatId) async {
    state = const AsyncLoading();
    try {
      final result = await _repository.joinGroup(chatId);
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    bool isSticker = false,
    String type = 'text',
  }) async {
    if (text.trim().isEmpty && !isSticker) return;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return _repository.sendMessage(
        chatId: chatId,
        senderId: senderId,
        text: text.trim(),
        isSticker: isSticker,
        type: type,
      );
    });
  }

  Future<void> markChatRead(String chatId) async {
    await _repository.markChatRead(chatId);
  }

  Future<ChatMediaAttachment> uploadMedia({
    required String chatId,
    required String kind,
    required String base64,
    required String fileName,
    required String mimeType,
  }) async {
    return _repository.uploadMedia(
      chatId: chatId,
      kind: kind,
      base64: base64,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  Future<void> deleteChat(String chatId) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _repository.deleteChat(chatId));
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.deleteMessage(chatId: chatId, messageId: messageId),
    );
  }

  Future<VerificationRequestInfo> requestVerification() async {
    state = const AsyncLoading();
    try {
      final result = await _repository.requestVerification();
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> reviewVerificationRequest({
    required String requesterId,
    required bool approve,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => _repository.reviewVerificationRequest(
        requesterId: requesterId,
        approve: approve,
      ),
    );
  }
}
