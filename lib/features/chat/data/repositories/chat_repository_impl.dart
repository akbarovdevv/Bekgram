import '../../../auth/domain/entities/app_user.dart';
import '../../domain/entities/chat_media_attachment.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/group_member.dart';
import '../../domain/entities/verification_request_info.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/chat_remote_data_source.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(this._remote);

  final ChatRemoteDataSource _remote;

  @override
  Stream<List<ChatThread>> watchChats(String userId) {
    return _remote.watchChats(userId);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId) {
    return _remote.watchMessages(chatId);
  }

  @override
  Stream<List<AppUser>> searchUsers(
      {required String query, required String excludeUserId}) {
    return _remote.searchUsers(query: query, excludeUserId: excludeUserId);
  }

  @override
  Stream<AppUser?> watchUser(String userId) {
    return _remote.watchUser(userId);
  }

  @override
  Future<String> getOrCreateDirectChat(
      {required String currentUserId, required AppUser peer}) {
    return _remote.getOrCreateDirectChat(
        currentUserId: currentUserId, peer: peer);
  }

  @override
  Future<String> getOrCreateSavedChat(String userId) {
    return _remote.getOrCreateSavedChat(userId);
  }

  @override
  Future<String> createGroup({
    required String title,
    required String groupUsername,
    required String bio,
    required bool isPublic,
    required List<String> memberUsernames,
  }) {
    return _remote.createGroup(
      title: title,
      groupUsername: groupUsername,
      bio: bio,
      isPublic: isPublic,
      memberUsernames: memberUsernames,
    );
  }

  @override
  Future<void> addGroupMembers({
    required String chatId,
    required List<String> memberUsernames,
  }) {
    return _remote.addGroupMembers(
      chatId: chatId,
      memberUsernames: memberUsernames,
    );
  }

  @override
  Future<List<GroupMember>> getGroupMembers(String chatId) {
    return _remote.getGroupMembers(chatId);
  }

  @override
  Future<void> removeGroupMember({
    required String chatId,
    required String memberId,
  }) {
    return _remote.removeGroupMember(
      chatId: chatId,
      memberId: memberId,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> searchPublicGroups(String query) {
    return _remote.searchPublicGroups(query);
  }

  @override
  Future<String> joinGroup(String chatId) {
    return _remote.joinGroup(chatId);
  }

  @override
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    required String text,
    bool isSticker = false,
    String type = 'text',
  }) {
    return _remote.sendMessage(
      chatId: chatId,
      senderId: senderId,
      text: text,
      isSticker: isSticker,
      type: type,
    );
  }

  @override
  Future<void> markChatRead(String chatId) {
    return _remote.markChatRead(chatId);
  }

  @override
  Future<ChatMediaAttachment> uploadMedia({
    required String chatId,
    required String kind,
    required String base64,
    required String fileName,
    required String mimeType,
  }) {
    return _remote.uploadMedia(
      chatId: chatId,
      kind: kind,
      base64: base64,
      fileName: fileName,
      mimeType: mimeType,
    );
  }

  @override
  Future<void> deleteChat(String chatId) {
    return _remote.deleteChat(chatId);
  }

  @override
  Future<void> deleteMessage({
    required String chatId,
    required String messageId,
  }) {
    return _remote.deleteMessage(chatId: chatId, messageId: messageId);
  }

  @override
  Future<VerificationRequestInfo> requestVerification() {
    return _remote.requestVerification();
  }

  @override
  Future<void> reviewVerificationRequest({
    required String requesterId,
    required bool approve,
  }) {
    return _remote.reviewVerificationRequest(
      requesterId: requesterId,
      approve: approve,
    );
  }
}
