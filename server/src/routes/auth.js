import { randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import bcrypt from 'bcryptjs';
import express from 'express';

import { createToken, authMiddleware } from '../lib/auth.js';
import { pool, query } from '../lib/db.js';
import { ApiError, asyncHandler } from '../lib/errors.js';
import { toUser } from '../lib/serializers.js';

const router = express.Router();
const uploadsDir = path.resolve(process.cwd(), 'uploads');

function normalizeUsername(username) {
  return String(username ?? '').trim().toLowerCase().replaceAll(' ', '');
}

function validateSignup({ username, password, displayName }) {
  const usernameLower = normalizeUsername(username);
  const validUsername = /^[a-z0-9_]{4,24}$/.test(usernameLower);
  if (!validUsername) {
    throw new ApiError(400, "Username 4-24 ta: a-z, 0-9 yoki _ bo'lishi kerak.");
  }

  if (String(password ?? '').length < 6) {
    throw new ApiError(400, "Parol kamida 6 ta belgidan iborat bo'lsin.");
  }

  if (String(displayName ?? '').trim().length < 2) {
    throw new ApiError(400, "Ism kamida 2 ta belgidan iborat bo'lsin.");
  }

  return usernameLower;
}

function defaultAvatar(displayName, username) {
  const label = String(displayName ?? '').trim() || username;
  return `https://ui-avatars.com/api/?background=229ED9&color=ffffff&name=${encodeURIComponent(label)}`;
}

function hasOwn(payload, key) {
  return Object.prototype.hasOwnProperty.call(payload, key);
}

function resolveImageExtension(mimeType, fileNameHint, base64Input) {
  const mime = String(mimeType ?? '').toLowerCase();
  const fileName = String(fileNameHint ?? '').toLowerCase();
  const dataPrefix = base64Input.startsWith('data:')
    ? base64Input.slice(0, base64Input.indexOf(';'))
    : '';

  if (
    mime.includes('png') ||
    fileName.endsWith('.png') ||
    dataPrefix.includes('image/png')
  ) {
    return 'png';
  }

  if (
    mime.includes('webp') ||
    fileName.endsWith('.webp') ||
    dataPrefix.includes('image/webp')
  ) {
    return 'webp';
  }

  if (
    mime.includes('gif') ||
    fileName.endsWith('.gif') ||
    dataPrefix.includes('image/gif')
  ) {
    return 'gif';
  }

  return 'jpg';
}

router.post(
  '/signup',
  asyncHandler(async (req, res) => {
    const usernameLower = validateSignup(req.body);
    const password = String(req.body.password ?? '');
    const displayName = String(req.body.displayName ?? '').trim();
    const bio = String(req.body.bio ?? '').trim() || 'New on Bekgram';
    const phoneNumber = String(req.body.phoneNumber ?? '').trim() || null;

    const existing = await query(
      'SELECT id FROM users WHERE username_lower = ? LIMIT 1',
      [usernameLower],
    );
    if (existing.length > 0) {
      throw new ApiError(409, `Bu username band: @${usernameLower}`);
    }

    const userId = randomUUID();
    const passwordHash = await bcrypt.hash(password, 10);
    const isVerified = (usernameLower === 'asilbek' || usernameLower === 'verify') ? 1 : 0;

    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();

      await connection.execute(
        `INSERT INTO users (
          id, username, username_lower, password_hash, display_name, bio, phone_number, avatar_url, is_verified, can_receive_messages, is_online, last_seen
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1, NOW())`,
        [
          userId,
          usernameLower,
          usernameLower,
          passwordHash,
          displayName,
          bio,
          phoneNumber,
          defaultAvatar(displayName, usernameLower),
          isVerified,
        ],
      );

      const savedChatId = randomUUID();
      await connection.execute(
        `INSERT INTO chats (id, type, direct_key, is_saved, last_message, last_sender_id, last_message_at)
         VALUES (?, 'saved', ?, 1, NULL, NULL, NULL)`,
        [
          savedChatId,
          `saved:${userId}`,
        ],
      );

      await connection.execute(
        'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?)',
        [savedChatId, userId, 'owner'],
      );

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const rows = await query('SELECT * FROM users WHERE id = ? LIMIT 1', [userId]);
    const token = createToken(userId);

    res.status(201).json({ token, user: toUser(rows[0]) });
  }),
);

router.post(
  '/login',
  asyncHandler(async (req, res) => {
    const usernameLower = normalizeUsername(req.body.username);
    const password = String(req.body.password ?? '');

    if (!usernameLower || !password) {
      throw new ApiError(400, 'Username va parol kiritilishi shart.');
    }

    const rows = await query(
      'SELECT * FROM users WHERE username_lower = ? LIMIT 1',
      [usernameLower],
    );

    if (rows.length === 0) {
      throw new ApiError(404, 'Username topilmadi.');
    }

    const user = rows[0];
    const ok = await bcrypt.compare(password, user.password_hash);
    if (!ok) {
      throw new ApiError(401, "Parol noto'g'ri.");
    }

    await query('UPDATE users SET is_online = 1, last_seen = NOW() WHERE id = ?', [user.id]);

    const refreshed = await query('SELECT * FROM users WHERE id = ? LIMIT 1', [user.id]);
    const token = createToken(user.id);

    res.json({ token, user: toUser(refreshed[0]) });
  }),
);

router.get(
  '/me',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const rows = await query('SELECT * FROM users WHERE id = ? LIMIT 1', [req.userId]);
    if (rows.length === 0) {
      throw new ApiError(404, 'Foydalanuvchi topilmadi.');
    }

    res.json({ user: toUser(rows[0]) });
  }),
);

router.put(
  '/me',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const payload = req.body ?? {};

    const rows = await query('SELECT * FROM users WHERE id = ? LIMIT 1', [req.userId]);
    if (rows.length === 0) {
      throw new ApiError(404, 'Foydalanuvchi topilmadi.');
    }

    const current = rows[0];

    let displayName = current.display_name;
    let bio = current.bio ?? '';
    let phoneNumber = current.phone_number ?? null;
    let avatarUrl = current.avatar_url ?? '';
    let canReceiveMessages = Boolean(current.can_receive_messages);

    if (hasOwn(payload, 'displayName')) {
      const nextDisplayName = String(payload.displayName ?? '').trim();
      if (nextDisplayName.length < 2 || nextDisplayName.length > 80) {
        throw new ApiError(400, "Ism 2 dan 80 belgigacha bo'lishi kerak.");
      }
      displayName = nextDisplayName;
    }

    if (hasOwn(payload, 'bio')) {
      bio = String(payload.bio ?? '').trim().slice(0, 255);
    }

    if (hasOwn(payload, 'phoneNumber')) {
      const rawPhone = String(payload.phoneNumber ?? '').trim();
      if (rawPhone.length > 32) {
        throw new ApiError(400, "Telefon raqam 32 belgidan oshmasligi kerak.");
      }
      phoneNumber = rawPhone || null;
    }

    if (hasOwn(payload, 'avatarUrl')) {
      const rawAvatarUrl = String(payload.avatarUrl ?? '').trim();
      if (rawAvatarUrl.length > 255) {
        throw new ApiError(400, 'Avatar URL juda uzun.');
      }
      avatarUrl = rawAvatarUrl;
    }

    if (hasOwn(payload, 'canReceiveMessages')) {
      canReceiveMessages = Boolean(payload.canReceiveMessages);
    }

    if (hasOwn(payload, 'avatarBase64')) {
      const rawBase64 = String(payload.avatarBase64 ?? '').trim();
      if (!rawBase64) {
        throw new ApiError(400, "Avatar fayl bo'sh.");
      }

      const rawBytes = rawBase64.startsWith('data:')
        ? rawBase64.slice(rawBase64.indexOf(',') + 1)
        : rawBase64;

      let bytes;
      try {
        bytes = Buffer.from(rawBytes, 'base64');
      } catch {
        throw new ApiError(400, "Avatar fayl formati noto'g'ri.");
      }

      if (!bytes.length) {
        throw new ApiError(400, "Avatar fayl bo'sh.");
      }

      if (bytes.length > 12 * 1024 * 1024) {
        throw new ApiError(413, "Avatar 12MB dan kichik bo'lishi kerak.");
      }

      const ext = resolveImageExtension(
        payload.avatarMimeType,
        payload.avatarFileName,
        rawBase64,
      );

      await fs.mkdir(uploadsDir, { recursive: true });
      const avatarFile = `avatar-${req.userId}-${Date.now()}.${ext}`;
      await fs.writeFile(path.join(uploadsDir, avatarFile), bytes);

      const host = `${req.protocol}://${req.get('host')}`;
      avatarUrl = `${host}/uploads/${avatarFile}`;
    }

    await query(
      `UPDATE users
       SET display_name = ?, bio = ?, phone_number = ?, avatar_url = ?, can_receive_messages = ?, updated_at = NOW()
       WHERE id = ?`,
      [displayName, bio, phoneNumber, avatarUrl, canReceiveMessages ? 1 : 0, req.userId],
    );

    const refreshed = await query('SELECT * FROM users WHERE id = ? LIMIT 1', [req.userId]);

    res.json({ user: toUser(refreshed[0]) });
  }),
);

router.post(
  '/presence',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const isOnline = Boolean(req.body?.isOnline);
    await query('UPDATE users SET is_online = ?, last_seen = NOW() WHERE id = ?', [isOnline ? 1 : 0, req.userId]);
    res.json({ ok: true });
  }),
);

router.post(
  '/logout',
  authMiddleware,
  asyncHandler(async (req, res) => {
    await query('UPDATE users SET is_online = 0, last_seen = NOW() WHERE id = ?', [req.userId]);
    res.json({ ok: true });
  }),
);

export default router;
