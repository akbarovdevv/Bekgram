import 'dart:async';

import '../../../auth/data/models/app_user_model.dart';
import '../../../auth/domain/entities/app_user.dart';
import '../../domain/entities/chat_media_attachment.dart';
import '../../domain/entities/verification_request_info.dart';
import '../../../../shared/network/api_client.dart';
import '../../../../shared/network/session_store.dart';
import '../../../../shared/network/socket_service.dart';
import '../models/chat_media_attachment_model.dart';
import '../models/chat_message_model.dart';
import '../models/chat_thread_model.dart';
import '../models/group_member_model.dart';

class ChatRemoteDataSource {
  ChatRemoteDataSource(
      this._apiClient, this._sessionStore, this._socketService);

  final ApiClient _apiClient;
  final SessionStore _sessionStore;
  final SocketService _socketService;

  Stream<List<ChatThreadModel>> watchChats(String userId) {
    final controller = StreamController<List<ChatThreadModel>>.broadcast();
    StreamSubscription? chatUpdateSub;
    StreamSubscription? messageSub;
    StreamSubscription? messageReadSub;
    StreamSubscription? messageDeletedSub;
    StreamSubscription? chatDeletedSub;

    Future<void> loadChats() async {
      try {
        final data = await _apiClient.get('/chats');
        final map = _asMap(data);
        final raw = map['chats'];
        final chats = raw is List
            ? raw.map((item) => ChatThreadModel.fromJson(_asMap(item))).toList()
            : <ChatThreadModel>[];
        controller.add(chats);
      } on ApiException catch (error) {
        controller.addError(error.message);
      } catch (_) {
        controller.addError('Chat list yuklashda xatolik yuz berdi.');
      }
    }

    controller.onListen = () async {
      await _sessionStore.ensureInitialized();
      final token = _sessionStore.token;
      if (token != null && token.isNotEmpty) {
        _socketService.connect(token);
      }

      await loadChats();
      chatUpdateSub =
          _socketService.chatUpdateStream.listen((_) => loadChats());
      messageSub = _socketService.messageStream.listen((_) => loadChats());
      messageReadSub =
          _socketService.messageReadStream.listen((_) => loadChats());
      messageDeletedSub =
          _socketService.messageDeletedStream.listen((_) => loadChats());
      chatDeletedSub =
          _socketService.chatDeletedStream.listen((_) => loadChats());
    };

    controller.onCancel = () async {
      await chatUpdateSub?.cancel();
      await messageSub?.cancel();
      await messageReadSub?.cancel();
      await messageDeletedSub?.cancel();
      await chatDeletedSub?.cancel();
    };

    return controller.stream;
  }

  Stream<List<ChatMessageModel>> watchMessages(String chatId) {
    final controller = StreamController<List<ChatMessageModel>>.broadcast();
    StreamSubscription? messageSub;
    StreamSubscription? messageReadSub;
    StreamSubscription? messageDeletedSub;
    StreamSubscription? chatDeletedSub;
    List<ChatMessageModel> messages = [];
    String currentUserId = '';

    Future<void> markReadSafe() async {
      try {
        await markChatRead(chatId);
      } catch (_) {
        // Read status should not block chat stream rendering.
      }
    }

    Future<void> loadMessages() async {
      try {
        final data = await _apiClient.get('/chats/$chatId/messages');
        final map = _asMap(data);
        final raw = map['messages'];
        messages = raw is List
            ? raw
                .map((item) => ChatMessageModel.fromJson(_asMap(item)))
                .toList()
            : <ChatMessageModel>[];
        controller.add(messages);
      } on ApiException catch (error) {
        controller.addError(error.message);
      } catch (_) {
        controller.addError('Xabarlarni yuklashda xatolik yuz berdi.');
      }
    }

    controller.onListen = () async {
      await _sessionStore.ensureInitialized();
      currentUserId = _sessionStore.user?.id ?? '';
      final token = _sessionStore.token;
      if (token != null && token.isNotEmpty) {
        _socketService.connect(token);
      }

      _socketService.joinChat(chatId);
      await loadMessages();
      await markReadSafe();

      messageSub = _socketService.messageStream.listen((payload) {
        final incoming = ChatMessageModel.fromJson(_asMap(payload));
        if (incoming.chatId != chatId) return;

        final exists = messages.any((m) => m.id == incoming.id);
        if (exists) return;

        messages = [...messages, incoming];
        controller.add(messages);

        if (incoming.senderId != currentUserId) {
          unawaited(markReadSafe());
        }
      });

      messageReadSub = _socketService.messageReadStream.listen((payload) {
        if (payload['chatId']?.toString() != chatId) return;

        final readerId = payload['readerId']?.toString() ?? '';
        final rawReadAt = payload['readAt'];
        final readAtText = rawReadAt?.toString() ?? '';
        final readAt = DateTime.tryParse(readAtText)?.toLocal();
        if (readAt == null) return;

        var hasChanges = false;
        final updated = messages.map((message) {
          if (message.readAt != null) return message;
          if (message.senderId == readerId) return message;
          if (message.createdAt.isAfter(readAt)) return message;
          hasChanges = true;
          return message.copyWith(readAt: readAt);
        }).toList();

        if (!hasChanges) return;
        messages = updated;
        controller.add(messages);
      });

      messageDeletedSub = _socketService.messageDeletedStream.listen((payload) {
        if (payload['chatId']?.toString() != chatId) return;
        final messageId = payload['messageId']?.toString();
        if (messageId == null || messageId.isEmpty) return;

        final before = messages.length;
        messages = messages.where((m) => m.id != messageId).toList();
        if (messages.length == before) return;
        controller.add(messages);
      });

      chatDeletedSub = _socketService.chatDeletedStream.listen((payload) {
        if (payload['chatId']?.toString() != chatId) return;
        controller.addError('Chat o\'chirildi.');
      });
    };

    controller.onCancel = () async {
      _socketService.leaveChat(chatId);
      await messageSub?.cancel();
      await messageReadSub?.cancel();
      await messageDeletedSub?.cancel();
      await chatDeletedSub?.cancel();
    };

    return controller.stream;
  }

  Stream<List<AppUserModel>> searchUsers({
    required String query,
    required String excludeUserId,
  }) {
    final normalized = query.trim();
    if (normalized.isEmpty) return Stream.value(const []);

    return Stream.fromFuture(
      (() async {
        final data = await _apiClient.get(
          '/users/search',
          query: {'q': normalized},
        );

        final map = _asMap(data);
        final rawUsers = map['users'];
        if (rawUsers is! List) return <AppUserModel>[];

        return rawUsers
            .map((item) => AppUserModel.fromJson(_asMap(item)))
            .where((user) => user.id != excludeUserId)
            .toList();
      })(),
    );
  }

  Stream<AppUserModel?> watchUser(String userId) {
    final controller = StreamController<AppUserModel?>.broadcast();
    StreamSubscription? presenceSub;

    Future<void> loadUser() async {
      try {
        final data = await _apiClient.get('/users/$userId');
        final map = _asMap(data);
        final rawUser = map['user'];
        if (rawUser == null) {
          controller.add(null);
          return;
        }

        controller.add(AppUserModel.fromJson(_asMap(rawUser)));
      } catch (_) {
        controller.add(null);
      }
    }

    controller.onListen = () async {
      await _sessionStore.ensureInitialized();
      final token = _sessionStore.token;
      if (token != null && token.isNotEmpty) {
        _socketService.connect(token);
      }

      await loadUser();

      presenceSub = _socketService.presenceStream.listen((payload) {
        final targetId = payload['userId']?.toString();
        if (targetId == userId) {
          loadUser();
        }
      });
    };

    controller.onCancel = () async {
      await presenceSub?.cancel();
    };

    return controller.stream;
  }

  Future<String> getOrCreateDirectChat({
    required String currentUserId,
    required AppUser peer,
  }) async {
    final data = await _apiClient.post(
      '/chats/direct',
      body: {'peerId': peer.id},
    );

    final map = _asMap(data);
    final chatId = map['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw ApiException('Chat ochilmadi.');
    }

    return chatId;
  }

  Future<String> getOrCreateSavedChat(String userId) async {
    final data = await _apiClient.post('/chats/saved', body: {});
    final map = _asMap(data);
    final chatId = map['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw ApiException('Saved chat ochilmadi.');
    }

    return chatId;
  }

  Future<String> createGroup({
    required String title,
    required String groupUsername,
    required String bio,
    required bool isPublic,
    required List<String> memberUsernames,
  }) async {
    final body = <String, dynamic>{
      'title': title,
      'bio': bio,
      'isPublic': isPublic,
      'memberUsernames': memberUsernames,
    };
    if (isPublic && groupUsername.isNotEmpty) {
      body['groupUsername'] = groupUsername;
    }
    final data = await _apiClient.post('/chats/group', body: body);
    final map = _asMap(data);
    final chatId = map['chatId']?.toString();
    if (chatId == null || chatId.isEmpty) {
      throw ApiException('Guruh yaratilmadi.');
    }
    return chatId;
  }

  Future<void> addGroupMembers({
    required String chatId,
    required List<String> memberUsernames,
  }) async {
    await _apiClient.post(
      '/chats/$chatId/group/members',
      body: {
        'memberUsernames': memberUsernames,
      },
    );
  }

  Future<List<GroupMemberModel>> getGroupMembers(String chatId) async {
    final data = await _apiClient.get('/chats/$chatId/group/members');
    final map = _asMap(data);
    final rawMembers = map['members'];
    if (rawMembers is! List) return const [];
    return rawMembers
        .map((item) => GroupMemberModel.fromJson(_asMap(item)))
        .toList();
  }

  Future<void> removeGroupMember({
    required String chatId,
    required String memberId,
  }) async {
    await _apiClient.delete('/chats/$chatId/group/members/$memberId');
  }

  Future<List<Map<String, dynamic>>> searchPublicGroups(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return const [];

    final data = await _apiClient.get(
      '/chats/groups/search',
      query: {'q': normalized},
    );
    final map = _asMap(data);
    final rawGroups = map['groups'];
    if (rawGroups is! List) return const [];
    return rawGroups.map((item) => _asMap(item)).toList();
  }

  Future<String> joinGroup(String chatId) async {
    final data = await _apiClient.post(
      '/chats/group/$chatId/join',
      body: <String, dynamic>{},
    );
    final map = _asMap(data);
    return map['chatId']?.toString() ?? chatId;
  }

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    bool isSticker = false,
    String type = 'text',
  }) async {
    await _apiClient.post(
      '/chats/$chatId/messages',
      body: {
        'text': text,
        'isSticker': isSticker,
        'type': type,
      },
    );
  }

  Future<void> markChatRead(String chatId) async {
    await _apiClient.post('/chats/$chatId/read', body: <String, dynamic>{});
  }

  Future<ChatMediaAttachment> uploadMedia({
    required String chatId,
    required String kind,
    required String base64,
    required String fileName,
    required String mimeType,
  }) async {
    final data = await _apiClient.post(
      '/chats/$chatId/upload',
      body: {
        'kind': kind,
        'base64': base64,
        'fileName': fileName,
        'mimeType': mimeType,
      },
    );
    final map = _asMap(data);
    final rawMedia = _asMap(map['media']);
    return ChatMediaAttachmentModel.fromJson(rawMedia);
  }

  Future<void> deleteChat(String chatId) async {
    await _apiClient.delete('/chats/$chatId');
  }

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    await _apiClient.delete('/chats/$chatId/messages/$messageId');
  }

  Future<VerificationRequestInfo> requestVerification() async {
    final data = await _apiClient.post(
      '/users/verification/request',
      body: <String, dynamic>{},
    );
    final map = _asMap(data);
    final chatId = (map['chatId'] ?? '').toString();
    final reviewerId = (map['reviewerId'] ?? '').toString();
    final message =
        (map['message'] ?? "Verification so'rovi yuborildi.").toString();

    if (chatId.isEmpty || reviewerId.isEmpty) {
      throw ApiException('Verification so\'rovi yuborilmadi.');
    }

    return VerificationRequestInfo(
      chatId: chatId,
      reviewerId: reviewerId,
      message: message,
    );
  }

  Future<void> reviewVerificationRequest({
    required String requesterId,
    required bool approve,
  }) async {
    await _apiClient.post(
      '/users/verification/decision',
      body: {
        'requesterId': requesterId,
        'approve': approve,
      },
    );
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }
}
