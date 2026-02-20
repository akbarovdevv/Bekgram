class VerificationRequestInfo {
  const VerificationRequestInfo({
    required this.chatId,
    required this.reviewerId,
    required this.message,
  });

  final String chatId;
  final String reviewerId;
  final String message;
}
