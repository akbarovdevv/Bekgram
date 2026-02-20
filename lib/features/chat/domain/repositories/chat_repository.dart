import '../../../auth/domain/entities/app_user.dart';
import '../entities/chat_media_attachment.dart';
import '../entities/chat_message.dart';
import '../entities/chat_thread.dart';
import '../entities/group_member.dart';
import '../entities/verification_request_info.dart';

abstract class ChatRepository {
  Stream<List<ChatThread>> watchChats(String userId);

  Stream<List<ChatMessage>> watchMessages(String chatId);

  Stream<List<AppUser>> searchUsers({
    required String query,
    required String excludeUserId,
  });

  Stream<AppUser?> watchUser(String userId);

  Future<String> getOrCreateDirectChat({
    required String currentUserId,
    required AppUser peer,
  });

  Future<String> getOrCreateSavedChat(String userId);

  Future<String> createGroup({
    required String title,
    required String groupUsername,
    required String bio,
    required bool isPublic,
    required List<String> memberUsernames,
  });

  Future<void> addGroupMembers({
    required String chatId,
    required List<String> memberUsernames,
  });

  Future<List<GroupMember>> getGroupMembers(String chatId);

  Future<void> removeGroupMember({
    required String chatId,
    required String memberId,
  });

  Future<List<Map<String, dynamic>>> searchPublicGroups(String query);

  Future<String> joinGroup(String chatId);

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    bool isSticker,
    String type,
  });

  Future<void> markChatRead(String chatId);

  Future<ChatMediaAttachment> uploadMedia({
    required String chatId,
    required String kind,
    required String base64,
    required String fileName,
    required String mimeType,
  });

  Future<void> deleteChat(String chatId);

  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  });

  Future<VerificationRequestInfo> requestVerification();

  Future<void> reviewVerificationRequest({
    required String requesterId,
    required bool approve,
  });
}
