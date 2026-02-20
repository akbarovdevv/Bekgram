import { query } from './db.js';

const migrations = [
  'ALTER TABLE users ADD COLUMN is_verified TINYINT(1) NOT NULL DEFAULT 0 AFTER avatar_url',
  'ALTER TABLE users ADD COLUMN can_receive_messages TINYINT(1) NOT NULL DEFAULT 1 AFTER avatar_url',
  'ALTER TABLE users ADD COLUMN verify_request_blocked_until DATETIME NULL AFTER can_receive_messages',
  "UPDATE users SET is_verified = 1 WHERE username_lower IN ('asilbek', 'verify')",
  'ALTER TABLE chat_members ADD COLUMN last_read_at DATETIME NULL AFTER joined_at',
  'ALTER TABLE messages ADD COLUMN read_at DATETIME NULL AFTER created_at',
  "ALTER TABLE messages MODIFY COLUMN type ENUM('text', 'sticker', 'image', 'video', 'voice', 'group_event') NOT NULL DEFAULT 'text'",
  'ALTER TABLE messages ADD INDEX idx_messages_chat_sender_read (chat_id, sender_id, read_at)',
  "ALTER TABLE chats MODIFY COLUMN type ENUM('direct', 'saved', 'group') NOT NULL",
  'ALTER TABLE chats ADD COLUMN title VARCHAR(120) NULL AFTER is_saved',
  'ALTER TABLE chats ADD COLUMN group_username VARCHAR(24) NULL AFTER title',
  'ALTER TABLE chats ADD COLUMN group_username_lower VARCHAR(24) NULL AFTER group_username',
  "ALTER TABLE chats ADD COLUMN group_bio VARCHAR(255) NOT NULL DEFAULT '' AFTER group_username_lower",
  'ALTER TABLE chats ADD COLUMN owner_id CHAR(36) NULL AFTER group_bio',
  'ALTER TABLE chats ADD UNIQUE INDEX uq_chats_group_username_lower (group_username_lower)',
  'ALTER TABLE chats ADD CONSTRAINT fk_chats_owner FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL',
  "ALTER TABLE chat_members ADD COLUMN role ENUM('owner', 'admin', 'member') NOT NULL DEFAULT 'member' AFTER user_id",
  `UPDATE chat_members cm
   INNER JOIN chats c ON c.id = cm.chat_id
   SET cm.role = CASE WHEN c.type = 'saved' THEN 'owner' ELSE 'member' END`,
  `UPDATE chats c
   SET c.last_message = NULL,
       c.last_sender_id = NULL,
       c.last_message_at = NULL
   WHERE c.last_message IN ('Conversation started', 'Your private notes')
     AND NOT EXISTS (
       SELECT 1
       FROM messages m
       WHERE m.chat_id = c.id
     )`,
  'ALTER TABLE chats ADD COLUMN is_public TINYINT(1) NOT NULL DEFAULT 0 AFTER owner_id',
];

const ignorableCodes = new Set([
  'ER_DUP_FIELDNAME',
  'ER_DUP_KEYNAME',
  'ER_DUP_ENTRY',
]);

export async function runMigrations() {
  for (const sql of migrations) {
    try {
      await query(sql);
    } catch (error) {
      if (ignorableCodes.has(error?.code)) continue;
      const normalizedSql = String(sql).toLowerCase();
      const isOwnerFkMigration =
        normalizedSql.includes('add constraint fk_chats_owner');
      const isDuplicateOwnerFk =
        isOwnerFkMigration &&
        (
          error?.code === 'ER_FK_DUP_NAME' ||
          error?.code === 'ER_CANT_CREATE_TABLE' ||
          error?.errno === 121 ||
          error?.errno === 1005
        );
      if (isDuplicateOwnerFk) continue;
      throw error;
    }
  }
}
