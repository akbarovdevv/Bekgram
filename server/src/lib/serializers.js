function toIso(value) {
  if (!value) return null;
  const d = value instanceof Date ? value : new Date(value);
  return d.toISOString();
}

export function toUser(row) {
  return {
    id: row.id,
    username: row.username,
    usernameLower: row.username_lower,
    displayName: row.display_name,
    email: `${row.username_lower}@bekgram.local`,
    avatarUrl: row.avatar_url,
    bio: row.bio,
    phoneNumber: row.phone_number,
    isVerified: Boolean(row.is_verified),
    canReceiveMessages: row.can_receive_messages == null
      ? true
      : Boolean(row.can_receive_messages),
    verifyRequestBlockedUntil: toIso(row.verify_request_blocked_until),
    isOnline: Boolean(row.is_online),
    createdAt: toIso(row.created_at),
    lastSeen: toIso(row.last_seen),
  };
}

export function toChat(row) {
  return {
    id: row.id,
    type: row.type,
    participantIds: String(row.participant_ids ?? '')
      .split(',')
      .filter(Boolean),
    isSaved: Boolean(row.is_saved),
    title: row.title ?? null,
    groupUsername: row.group_username ?? null,
    groupBio: row.group_bio ?? '',
    ownerId: row.owner_id ?? null,
    isPublic: Boolean(row.is_public),
    lastMessage: row.last_message,
    lastSenderId: row.last_sender_id,
    lastMessageAt: toIso(row.last_message_at),
    updatedAt: toIso(row.updated_at),
    unreadCount: Number(row.unread_count ?? 0),
    canWrite: row.can_write == null ? true : Boolean(row.can_write),
    memberCount: Number(row.member_count ?? 0),
    myRole: row.my_role ?? 'member',
  };
}

export function toMessage(row) {
  return {
    id: String(row.id),
    chatId: row.chat_id,
    senderId: row.sender_id,
    text: row.text,
    type: row.type,
    createdAt: toIso(row.created_at),
    readAt: toIso(row.read_at),
  };
}
