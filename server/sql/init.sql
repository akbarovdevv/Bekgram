CREATE DATABASE IF NOT EXISTS bekgram_local CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'bekgram_app'@'localhost' IDENTIFIED BY 'Bekgram@2026';
CREATE USER IF NOT EXISTS 'bekgram_app'@'%' IDENTIFIED BY 'Bekgram@2026';
ALTER USER 'bekgram_app'@'localhost' IDENTIFIED BY 'Bekgram@2026';
ALTER USER 'bekgram_app'@'%' IDENTIFIED BY 'Bekgram@2026';

GRANT ALL PRIVILEGES ON bekgram_local.* TO 'bekgram_app'@'localhost';
GRANT ALL PRIVILEGES ON bekgram_local.* TO 'bekgram_app'@'%';
FLUSH PRIVILEGES;

USE bekgram_local;

CREATE TABLE IF NOT EXISTS users (
  id CHAR(36) PRIMARY KEY,
  username VARCHAR(24) NOT NULL UNIQUE,
  username_lower VARCHAR(24) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  display_name VARCHAR(80) NOT NULL,
  bio VARCHAR(255) NOT NULL DEFAULT '',
  phone_number VARCHAR(32) NULL,
  avatar_url VARCHAR(255) NOT NULL DEFAULT '',
  is_verified TINYINT(1) NOT NULL DEFAULT 0,
  can_receive_messages TINYINT(1) NOT NULL DEFAULT 1,
  verify_request_blocked_until DATETIME NULL,
  is_online TINYINT(1) NOT NULL DEFAULT 0,
  last_seen DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS chats (
  id CHAR(36) PRIMARY KEY,
  type ENUM('direct', 'saved', 'group') NOT NULL,
  direct_key VARCHAR(100) NULL UNIQUE,
  is_saved TINYINT(1) NOT NULL DEFAULT 0,
  title VARCHAR(120) NULL,
  group_username VARCHAR(24) NULL,
  group_username_lower VARCHAR(24) NULL UNIQUE,
  group_bio VARCHAR(255) NOT NULL DEFAULT '',
  owner_id CHAR(36) NULL,
  last_message TEXT NULL,
  last_sender_id CHAR(36) NULL,
  last_message_at DATETIME NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_chats_owner FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE SET NULL,
  CONSTRAINT fk_chats_last_sender FOREIGN KEY (last_sender_id) REFERENCES users(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS chat_members (
  chat_id CHAR(36) NOT NULL,
  user_id CHAR(36) NOT NULL,
  role ENUM('owner', 'admin', 'member') NOT NULL DEFAULT 'member',
  joined_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_read_at DATETIME NULL,
  PRIMARY KEY (chat_id, user_id),
  CONSTRAINT fk_chat_members_chat FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
  CONSTRAINT fk_chat_members_user FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  chat_id CHAR(36) NOT NULL,
  sender_id CHAR(36) NOT NULL,
  text TEXT NOT NULL,
  type ENUM('text', 'sticker', 'image', 'video', 'voice') NOT NULL DEFAULT 'text',
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  read_at DATETIME NULL,
  CONSTRAINT fk_messages_chat FOREIGN KEY (chat_id) REFERENCES chats(id) ON DELETE CASCADE,
  CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
  INDEX idx_messages_chat_created (chat_id, created_at),
  INDEX idx_messages_chat_sender_read (chat_id, sender_id, read_at)
);
