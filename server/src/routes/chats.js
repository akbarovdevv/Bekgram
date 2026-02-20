import { randomUUID } from 'node:crypto';
import { promises as fs } from 'node:fs';
import path from 'node:path';

import express from 'express';

import { authMiddleware } from '../lib/auth.js';
import { pool, query } from '../lib/db.js';
import { ApiError, asyncHandler } from '../lib/errors.js';
import { toChat, toMessage } from '../lib/serializers.js';

const router = express.Router();
const uploadsDir = path.resolve(process.cwd(), 'uploads');
const allowedMessageTypes = new Set(['text', 'sticker', 'image', 'video', 'voice']);
const allowedMediaKinds = new Set(['image', 'video', 'voice']);
const groupUsernameRegex = /^[a-z0-9_]{4,24}$/;

function normalizeGroupUsername(value) {
  const raw = String(value ?? '').trim().toLowerCase().replaceAll(' ', '');
  return raw.startsWith('@') ? raw.slice(1) : raw;
}

function parseUsernameList(input) {
  if (!Array.isArray(input)) return [];
  const out = [];
  const seen = new Set();
  for (const raw of input) {
    const normalized = normalizeGroupUsername(raw);
    if (!normalized) continue;
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    out.push(normalized);
  }
  return out;
}

function buildPlaceholders(count) {
  return Array.from({ length: count }, () => '?').join(', ');
}

function buildGroupEventText({
  action,
  actor,
  target,
}) {
  return JSON.stringify({
    kind: 'group_event',
    action,
    actorId: actor.id,
    actorUsername: actor.username,
    actorDisplayName: actor.display_name,
    targetId: target.id,
    targetUsername: target.username,
    targetDisplayName: target.display_name,
    at: new Date().toISOString(),
  });
}

function buildGroupEventSummary(action, actor, target) {
  if (action === 'joined') {
    return `${target.display_name} joined`;
  }
  if (action === 'added') {
    return `${actor.display_name} added ${target.display_name}`;
  }
  if (action === 'removed') {
    return `${actor.display_name} removed ${target.display_name}`;
  }
  return 'Group update';
}

async function assertMembership(chatId, userId, connection = null) {
  const executor = connection ?? pool;
  const [rows] = await executor.execute(
    'SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ? LIMIT 1',
    [chatId, userId],
  );

  if (rows.length === 0) {
    throw new ApiError(403, 'Bu chatga ruxsat yoq.');
  }
}

function buildLastMessageSummary(type, text) {
  if (type === 'sticker') return 'Sticker';
  if (type === 'image') return 'Photo';
  if (type === 'video') return 'Video';
  if (type === 'voice') return 'Voice message';
  const trimmed = String(text ?? '').trim();
  if (trimmed.startsWith('{')) {
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed?.kind === 'verify_request') return 'Verification request';
      if (parsed?.kind === 'verify_decision') {
        return parsed?.approved === true
          ? 'Verification approved'
          : 'Verification rejected';
      }
      if (parsed?.kind === 'group_event') {
        if (parsed?.action === 'joined') {
          return `${parsed?.targetDisplayName ?? parsed?.targetUsername ?? 'User'} joined`;
        }
        if (parsed?.action === 'added') {
          return `${parsed?.actorDisplayName ?? parsed?.actorUsername ?? 'Admin'} added ${parsed?.targetDisplayName ?? parsed?.targetUsername ?? 'member'}`;
        }
        if (parsed?.action === 'removed') {
          return `${parsed?.actorDisplayName ?? parsed?.actorUsername ?? 'Admin'} removed ${parsed?.targetDisplayName ?? parsed?.targetUsername ?? 'member'}`;
        }
      }
    } catch {
      // Ignore malformed JSON-like text.
    }
  }
  return trimmed.slice(0, 300);
}

async function refreshChatPreview(chatId, connection) {
  const [latestRows] = await connection.execute(
    `SELECT sender_id, text, type, created_at
     FROM messages
     WHERE chat_id = ?
     ORDER BY created_at DESC, id DESC
     LIMIT 1`,
    [chatId],
  );

  if (latestRows.length === 0) {
    await connection.execute(
      `UPDATE chats
       SET last_message = NULL,
           last_sender_id = NULL,
           last_message_at = NULL,
           updated_at = NOW()
       WHERE id = ?`,
      [chatId],
    );
    return;
  }

  const latest = latestRows[0];
  await connection.execute(
    `UPDATE chats
     SET last_message = ?,
         last_sender_id = ?,
         last_message_at = ?,
         updated_at = NOW()
     WHERE id = ?`,
    [
      buildLastMessageSummary(latest.type, latest.text),
      latest.sender_id,
      latest.created_at,
      chatId,
    ],
  );
}

async function resolveWritePermission(chatId, userId, connection = null) {
  const executor = connection ?? pool;
  const [rows] = await executor.execute(
    `SELECT
       c.id,
       c.type,
       c.is_saved,
       peer.user_id AS peer_id,
       COALESCE(u.can_receive_messages, 1) AS peer_accepts_messages
     FROM chats c
     LEFT JOIN chat_members peer
       ON peer.chat_id = c.id
      AND peer.user_id <> ?
     LEFT JOIN users u ON u.id = peer.user_id
     WHERE c.id = ?
     LIMIT 1`,
    [userId, chatId],
  );

  if (rows.length === 0) {
    throw new ApiError(404, 'Chat topilmadi.');
  }

  return {
    type: String(rows[0].type ?? ''),
    isSaved: Boolean(rows[0].is_saved),
    peerId: rows[0].peer_id ?? null,
    peerAcceptsMessages: Boolean(rows[0].peer_accepts_messages),
  };
}

function assertWriteAllowed(permission) {
  if (permission.isSaved) return;
  if (permission.type === 'group') return;
  if (permission.peerId == null) return;
  if (!permission.peerAcceptsMessages) {
    throw new ApiError(403, "Bu foydalanuvchi sizdan xabar qabul qilmaydi.");
  }
}

function parseBase64Input(rawInput) {
  const value = String(rawInput ?? '').trim();
  if (!value) {
    throw new ApiError(400, "Fayl bo'sh.");
  }

  const isDataUrl = value.startsWith('data:') && value.includes(',');
  if (isDataUrl) {
    const commaIndex = value.indexOf(',');
    const header = value.slice(0, commaIndex);
    const bytesBase64 = value.slice(commaIndex + 1);
    const mimeType = header.split(';')[0].replace('data:', '').trim().toLowerCase();
    return {
      mimeType,
      bytes: Buffer.from(bytesBase64, 'base64'),
    };
  }

  return {
    mimeType: '',
    bytes: Buffer.from(value, 'base64'),
  };
}

function resolveMediaExtension(kind, mimeType, fileName) {
  const mime = String(mimeType ?? '').toLowerCase();
  const name = String(fileName ?? '').toLowerCase();

  if (kind === 'image') {
    if (mime.includes('png') || name.endsWith('.png')) return 'png';
    if (mime.includes('webp') || name.endsWith('.webp')) return 'webp';
    if (mime.includes('gif') || name.endsWith('.gif')) return 'gif';
    return 'jpg';
  }

  if (kind === 'video') {
    if (mime.includes('webm') || name.endsWith('.webm')) return 'webm';
    if (mime.includes('quicktime') || name.endsWith('.mov')) return 'mov';
    return 'mp4';
  }

  if (mime.includes('ogg') || name.endsWith('.ogg') || name.endsWith('.oga')) return 'ogg';
  if (mime.includes('webm') || name.endsWith('.webm')) return 'webm';
  if (mime.includes('opus') || name.endsWith('.opus')) return 'opus';
  if (mime.includes('pcm') || name.endsWith('.pcm')) return 'pcm';
  if (mime.includes('wav') || name.endsWith('.wav')) return 'wav';
  if (mime.includes('aac') || name.endsWith('.aac')) return 'aac';
  if (mime.includes('m4a') || name.endsWith('.m4a')) return 'm4a';
  return 'mp3';
}

async function markChatRead({
  chatId,
  userId,
  io,
}) {
  const connection = await pool.getConnection();
  let senderIds = [];
  let updatedCount = 0;
  const readAt = new Date().toISOString();

  try {
    await connection.beginTransaction();
    await assertMembership(chatId, userId, connection);

    const [senderRows] = await connection.execute(
      `SELECT DISTINCT sender_id
       FROM messages
       WHERE chat_id = ?
         AND sender_id <> ?
         AND read_at IS NULL`,
      [chatId, userId],
    );
    senderIds = senderRows.map((row) => row.sender_id);

    const [updateResult] = await connection.execute(
      `UPDATE messages
       SET read_at = NOW()
       WHERE chat_id = ?
         AND sender_id <> ?
         AND read_at IS NULL`,
      [chatId, userId],
    );
    updatedCount = Number(updateResult.affectedRows ?? 0);

    await connection.execute(
      `UPDATE chat_members
       SET last_read_at = NOW()
       WHERE chat_id = ? AND user_id = ?`,
      [chatId, userId],
    );

    await connection.commit();
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }

  if (io) {
    io.to(`user:${userId}`).emit('chat:updated', {
      chatId,
      at: readAt,
    });

    if (updatedCount > 0) {
      const payload = {
        chatId,
        readerId: userId,
        readAt,
      };

      io.to(`chat:${chatId}`).emit('message:read', payload);
      for (const senderId of senderIds) {
        io.to(`user:${senderId}`).emit('chat:updated', {
          chatId,
          at: readAt,
        });
        io.to(`user:${senderId}`).emit('message:read', payload);
      }
    }
  }

  return {
    readAt,
    updatedCount,
  };
}

router.get(
  '/',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const rows = await query(
      `SELECT
          c.id,
          c.type,
          c.is_saved,
          c.title,
          c.group_username,
          c.group_bio,
          c.owner_id,
          c.is_public,
          my.role AS my_role,
          c.last_message,
          c.last_sender_id,
          c.last_message_at,
          c.updated_at,
          GROUP_CONCAT(cm.user_id ORDER BY cm.user_id SEPARATOR ',') AS participant_ids,
          COUNT(cm.user_id) AS member_count,
          (
            SELECT COUNT(*)
            FROM messages m
            WHERE m.chat_id = c.id
              AND m.sender_id <> my.user_id
              AND (
                my.last_read_at IS NULL
                OR m.created_at > my.last_read_at
              )
          ) AS unread_count,
          CASE
            WHEN c.type = 'group' THEN 1
            WHEN c.is_saved = 1 THEN 1
            ELSE COALESCE(
              (
                SELECT u.can_receive_messages
                FROM chat_members cm2
                INNER JOIN users u ON u.id = cm2.user_id
                WHERE cm2.chat_id = c.id
                  AND cm2.user_id <> my.user_id
                LIMIT 1
              ),
              1
            )
          END AS can_write
       FROM chats c
       INNER JOIN chat_members my ON my.chat_id = c.id AND my.user_id = ?
       INNER JOIN chat_members cm ON cm.chat_id = c.id
       GROUP BY c.id, my.user_id, my.last_read_at, my.role
       ORDER BY COALESCE(c.last_message_at, c.updated_at) DESC`,
      [req.userId],
    );

    res.json({ chats: rows.map(toChat) });
  }),
);

router.post(
  '/saved',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const directKey = `saved:${req.userId}`;
    const existing = await query(
      'SELECT id FROM chats WHERE direct_key = ? LIMIT 1',
      [directKey],
    );

    if (existing.length > 0) {
      return res.json({ chatId: existing[0].id });
    }

    const chatId = randomUUID();
    const connection = await pool.getConnection();

    try {
      await connection.beginTransaction();
      await connection.execute(
        `INSERT INTO chats (id, type, direct_key, is_saved, last_message, last_sender_id, last_message_at)
         VALUES (?, 'saved', ?, 1, NULL, NULL, NULL)`,
        [chatId, directKey],
      );
      await connection.execute(
        'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?)',
        [chatId, req.userId, 'owner'],
      );
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      if (error.code === 'ER_DUP_ENTRY') {
        const fallback = await query(
          'SELECT id FROM chats WHERE direct_key = ? LIMIT 1',
          [directKey],
        );
        if (fallback.length > 0) {
          return res.json({ chatId: fallback[0].id });
        }
      }
      throw error;
    } finally {
      connection.release();
    }

    return res.json({ chatId });
  }),
);

router.post(
  '/direct',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const peerId = String(req.body?.peerId ?? '').trim();
    if (!peerId) throw new ApiError(400, 'peerId berilishi shart.');
    if (peerId === req.userId) throw new ApiError(400, "O'zingiz bilan DM ochib bo'lmaydi.");

    const users = await query('SELECT id FROM users WHERE id IN (?, ?) ORDER BY id', [
      req.userId,
      peerId,
    ]);
    if (users.length < 2) {
      throw new ApiError(404, 'Peer user topilmadi.');
    }

    const sorted = [req.userId, peerId].sort();
    const directKey = `direct:${sorted[0]}_${sorted[1]}`;

    const existing = await query(
      'SELECT id FROM chats WHERE direct_key = ? LIMIT 1',
      [directKey],
    );
    if (existing.length > 0) {
      return res.json({ chatId: existing[0].id });
    }

    const chatId = randomUUID();
    const connection = await pool.getConnection();

    try {
      await connection.beginTransaction();
      await connection.execute(
        `INSERT INTO chats (id, type, direct_key, is_saved, last_message, last_sender_id, last_message_at)
         VALUES (?, 'direct', ?, 0, NULL, NULL, NULL)`,
        [chatId, directKey],
      );
      await connection.execute(
        'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?), (?, ?, ?)',
        [chatId, req.userId, 'member', chatId, peerId, 'member'],
      );
      await connection.commit();
    } catch (error) {
      await connection.rollback();
      if (error.code === 'ER_DUP_ENTRY') {
        const fallback = await query(
          'SELECT id FROM chats WHERE direct_key = ? LIMIT 1',
          [directKey],
        );
        if (fallback.length > 0) {
          return res.json({ chatId: fallback[0].id });
        }
      }
      throw error;
    } finally {
      connection.release();
    }

    return res.json({ chatId });
  }),
);

router.post(
  '/group',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const title = String(req.body?.title ?? '').trim();
    const isPublic = req.body?.isPublic === true;
    const groupUsernameRaw = String(req.body?.groupUsername ?? '').trim();
    const groupUsernameLower = normalizeGroupUsername(groupUsernameRaw);
    const groupBio = String(req.body?.bio ?? '').trim();
    const requestedMembers = parseUsernameList(req.body?.memberUsernames);

    if (title.length < 2 || title.length > 120) {
      throw new ApiError(400, "Guruh nomi 2-120 ta belgidan iborat bo'lishi kerak.");
    }
    if (isPublic) {
      if (!groupUsernameRegex.test(groupUsernameLower)) {
        throw new ApiError(400, "Guruh username 4-24 ta: a-z, 0-9 yoki _ bo'lishi kerak.");
      }
    }
    if (groupBio.length > 255) {
      throw new ApiError(400, "Guruh bio 255 ta belgidan oshmasin.");
    }

    const connection = await pool.getConnection();
    let chatId = '';
    let participantIds = [];
    let messagePayloads = [];

    try {
      await connection.beginTransaction();

      const [creatorRows] = await connection.execute(
        'SELECT id, username, username_lower, display_name FROM users WHERE id = ? LIMIT 1',
        [req.userId],
      );
      if (creatorRows.length === 0) {
        throw new ApiError(404, 'Owner user topilmadi.');
      }
      const creator = creatorRows[0];
      const memberUsernames = requestedMembers.filter(
        (usernameLower) => usernameLower !== creator.username_lower,
      );
      if (memberUsernames.length > 100) {
        throw new ApiError(400, "Bitta guruhga birdaniga ko'pi bilan 100 ta user qo'shing.");
      }

      if (isPublic && groupUsernameLower) {
        const [existingGroupRows] = await connection.execute(
          'SELECT id FROM chats WHERE group_username_lower = ? LIMIT 1',
          [groupUsernameLower],
        );
        if (existingGroupRows.length > 0) {
          throw new ApiError(409, `Bu group username band: @${groupUsernameLower}`);
        }
      }

      let memberRows = [];
      if (memberUsernames.length > 0) {
        const placeholders = buildPlaceholders(memberUsernames.length);
        const [rows] = await connection.execute(
          `SELECT id, username, username_lower, display_name
           FROM users
           WHERE username_lower IN (${placeholders})`,
          memberUsernames,
        );
        memberRows = rows;

        const foundUsernames = new Set(rows.map((row) => row.username_lower));
        const missingUsernames = memberUsernames.filter((u) => !foundUsernames.has(u));
        if (missingUsernames.length > 0) {
          throw new ApiError(404, `Topilmagan username: ${missingUsernames.map((u) => `@${u}`).join(', ')}`);
        }
      }

      const finalUsername = isPublic ? groupUsernameLower : null;
      chatId = randomUUID();
      await connection.execute(
        `INSERT INTO chats (
          id, type, direct_key, is_saved, title, group_username, group_username_lower, group_bio, owner_id, is_public,
          last_message, last_sender_id, last_message_at
        ) VALUES (?, 'group', NULL, 0, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL)`,
        [chatId, title, finalUsername, finalUsername, groupBio, req.userId, isPublic ? 1 : 0],
      );

      await connection.execute(
        'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?)',
        [chatId, req.userId, 'owner'],
      );

      const addedMembers = [];
      for (const member of memberRows) {
        await connection.execute(
          'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?)',
          [chatId, member.id, 'member'],
        );
        addedMembers.push(member);
      }

      let latestSummary = null;
      for (const member of addedMembers) {
        const eventText = buildGroupEventText({
          action: 'joined',
          actor: creator,
          target: member,
        });
        const [insertResult] = await connection.execute(
          `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
           VALUES (?, ?, ?, 'group_event', NULL)`,
          [chatId, req.userId, eventText],
        );
        latestSummary = buildGroupEventSummary('joined', creator, member);
        const [messageRows] = await connection.execute(
          `SELECT id, chat_id, sender_id, text, type, created_at, read_at
           FROM messages
           WHERE id = ?
           LIMIT 1`,
          [insertResult.insertId],
        );
        messagePayloads.push(toMessage(messageRows[0]));
      }

      if (latestSummary != null) {
        await connection.execute(
          `UPDATE chats
           SET last_message = ?,
               last_sender_id = ?,
               last_message_at = NOW(),
               updated_at = NOW()
           WHERE id = ?`,
          [latestSummary, req.userId, chatId],
        );
      }

      const [participantRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      participantIds = participantRows.map((row) => row.user_id);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:updated', {
          chatId,
          at: new Date().toISOString(),
        });
        for (const payload of messagePayloads) {
          io.to(`user:${uid}`).emit('message:new', payload);
        }
      }
      for (const payload of messagePayloads) {
        io.to(`chat:${chatId}`).emit('message:new', payload);
      }
    }

    return res.status(201).json({
      chatId,
      message: 'Guruh yaratildi.',
    });
  }),
);

router.post(
  '/:chatId/group/members',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    const requestedMembers = parseUsernameList(
      req.body?.memberUsernames ?? req.body?.usernames,
    );
    if (requestedMembers.length === 0) {
      throw new ApiError(400, "Qo'shish uchun kamida 1 ta username yuboring.");
    }

    const connection = await pool.getConnection();
    let participantIds = [];
    let addedCount = 0;
    let messagePayloads = [];

    try {
      await connection.beginTransaction();
      await assertMembership(chatId, req.userId, connection);

      const [chatRows] = await connection.execute(
        'SELECT id, type, owner_id FROM chats WHERE id = ? LIMIT 1',
        [chatId],
      );
      if (chatRows.length === 0) {
        throw new ApiError(404, 'Chat topilmadi.');
      }
      const chat = chatRows[0];
      if (chat.type !== 'group') {
        throw new ApiError(400, 'Bu chat guruh emas.');
      }
      if (chat.owner_id !== req.userId) {
        throw new ApiError(403, "Faqat group owner odam qo'sha oladi.");
      }

      const [actorRows] = await connection.execute(
        'SELECT id, username, display_name FROM users WHERE id = ? LIMIT 1',
        [req.userId],
      );
      if (actorRows.length === 0) {
        throw new ApiError(404, 'Owner user topilmadi.');
      }
      const actor = actorRows[0];

      const placeholders = buildPlaceholders(requestedMembers.length);
      const [userRows] = await connection.execute(
        `SELECT id, username, username_lower, display_name
         FROM users
         WHERE username_lower IN (${placeholders})`,
        requestedMembers,
      );

      const foundUsernames = new Set(userRows.map((row) => row.username_lower));
      const missingUsernames = requestedMembers.filter((u) => !foundUsernames.has(u));
      if (missingUsernames.length > 0) {
        throw new ApiError(404, `Topilmagan username: ${missingUsernames.map((u) => `@${u}`).join(', ')}`);
      }

      const [existingMemberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      const existingMemberIds = new Set(existingMemberRows.map((row) => row.user_id));

      const addedMembers = [];
      for (const userRow of userRows) {
        if (userRow.id === req.userId) continue;
        if (existingMemberIds.has(userRow.id)) continue;
        await connection.execute(
          'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?)',
          [chatId, userRow.id, 'member'],
        );
        existingMemberIds.add(userRow.id);
        addedCount += 1;
        addedMembers.push(userRow);
      }

      let latestSummary = null;
      for (const member of addedMembers) {
        const eventText = buildGroupEventText({
          action: 'added',
          actor,
          target: member,
        });
        const [insertResult] = await connection.execute(
          `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
           VALUES (?, ?, ?, 'group_event', NULL)`,
          [chatId, req.userId, eventText],
        );
        latestSummary = buildGroupEventSummary('added', actor, member);
        const [messageRows] = await connection.execute(
          `SELECT id, chat_id, sender_id, text, type, created_at, read_at
           FROM messages
           WHERE id = ?
           LIMIT 1`,
          [insertResult.insertId],
        );
        messagePayloads.push(toMessage(messageRows[0]));
      }

      if (latestSummary != null) {
        await connection.execute(
          `UPDATE chats
           SET last_message = ?,
               last_sender_id = ?,
               last_message_at = NOW(),
               updated_at = NOW()
           WHERE id = ?`,
          [latestSummary, req.userId, chatId],
        );
      }

      const [allMemberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      participantIds = allMemberRows.map((row) => row.user_id);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:updated', {
          chatId,
          at: new Date().toISOString(),
        });
        for (const payload of messagePayloads) {
          io.to(`user:${uid}`).emit('message:new', payload);
        }
      }
      for (const payload of messagePayloads) {
        io.to(`chat:${chatId}`).emit('message:new', payload);
      }
    }

    return res.json({
      ok: true,
      addedCount,
      message: addedCount > 0
        ? `${addedCount} ta a'zo qo'shildi.`
        : "Yangi a'zo qo'shilmadi.",
    });
  }),
);

router.get(
  '/groups/search',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const q = String(req.query.q ?? '').trim().toLowerCase();
    if (!q) {
      return res.json({ groups: [] });
    }

    const rows = await query(
      `SELECT
         c.id,
         c.title,
         c.group_username,
         c.group_bio,
         c.is_public,
         (SELECT COUNT(*) FROM chat_members cm WHERE cm.chat_id = c.id) AS member_count,
         EXISTS(
           SELECT 1 FROM chat_members cm2
           WHERE cm2.chat_id = c.id AND cm2.user_id = ?
         ) AS is_member
       FROM chats c
       WHERE c.type = 'group'
         AND c.is_public = 1
         AND c.group_username_lower LIKE ?
       ORDER BY c.group_username_lower ASC
       LIMIT 20`,
      [req.userId, `${q}%`],
    );

    const groups = rows.map((row) => ({
      id: row.id,
      title: row.title,
      groupUsername: row.group_username,
      groupBio: row.group_bio ?? '',
      memberCount: Number(row.member_count ?? 0),
      isMember: Boolean(row.is_member),
    }));

    return res.json({ groups });
  }),
);

router.post(
  '/group/:chatId/join',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;

    const connection = await pool.getConnection();
    let participantIds = [];
    let messagePayload = null;

    try {
      await connection.beginTransaction();

      const [chatRows] = await connection.execute(
        'SELECT id, type, is_public FROM chats WHERE id = ? LIMIT 1',
        [chatId],
      );
      if (chatRows.length === 0) {
        throw new ApiError(404, 'Chat topilmadi.');
      }
      const chat = chatRows[0];
      if (chat.type !== 'group') {
        throw new ApiError(400, 'Bu chat guruh emas.');
      }
      if (!chat.is_public) {
        throw new ApiError(403, 'Bu guruh private. Qo\'shilish mumkin emas.');
      }

      const [existingRows] = await connection.execute(
        'SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ? LIMIT 1',
        [chatId, req.userId],
      );
      if (existingRows.length > 0) {
        await connection.rollback();
        connection.release();
        return res.json({ ok: true, chatId, message: 'Siz allaqachon a\'zosiz.' });
      }

      await connection.execute(
        'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?)',
        [chatId, req.userId, 'member'],
      );

      const [userRows] = await connection.execute(
        'SELECT id, username, username_lower, display_name FROM users WHERE id = ? LIMIT 1',
        [req.userId],
      );
      const joiner = userRows[0];

      const eventText = buildGroupEventText({
        action: 'joined',
        actor: joiner,
        target: joiner,
      });
      const [insertResult] = await connection.execute(
        `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
         VALUES (?, ?, ?, 'group_event', NULL)`,
        [chatId, req.userId, eventText],
      );

      const summary = buildGroupEventSummary('joined', joiner, joiner);
      await connection.execute(
        `UPDATE chats
         SET last_message = ?,
             last_sender_id = ?,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = ?`,
        [summary, req.userId, chatId],
      );

      const [messageRows] = await connection.execute(
        `SELECT id, chat_id, sender_id, text, type, created_at, read_at
         FROM messages
         WHERE id = ?
         LIMIT 1`,
        [insertResult.insertId],
      );
      messagePayload = toMessage(messageRows[0]);

      const [memberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      participantIds = memberRows.map((row) => row.user_id);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:updated', {
          chatId,
          at: new Date().toISOString(),
        });
        if (messagePayload) {
          io.to(`user:${uid}`).emit('message:new', messagePayload);
        }
      }
      if (messagePayload) {
        io.to(`chat:${chatId}`).emit('message:new', messagePayload);
      }
    }

    return res.status(201).json({
      ok: true,
      chatId,
      message: 'Guruhga qo\'shildingiz.',
    });
  }),
);

router.get(
  '/:chatId/group/members',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    await assertMembership(chatId, req.userId);

    const chatRows = await query(
      'SELECT type FROM chats WHERE id = ? LIMIT 1',
      [chatId],
    );
    if (chatRows.length === 0) {
      throw new ApiError(404, 'Chat topilmadi.');
    }
    if (chatRows[0].type !== 'group') {
      throw new ApiError(400, 'Bu chat guruh emas.');
    }

    const rows = await query(
      `SELECT
         u.id,
         u.username,
         u.display_name,
         u.avatar_url,
         u.is_online,
         u.last_seen,
         u.is_verified,
         cm.role
       FROM chat_members cm
       INNER JOIN users u ON u.id = cm.user_id
       WHERE cm.chat_id = ?
       ORDER BY FIELD(cm.role, 'owner', 'admin', 'member'), u.display_name ASC, u.username ASC`,
      [chatId],
    );

    const members = rows.map((row) => ({
      id: row.id,
      username: row.username,
      displayName: row.display_name,
      avatarUrl: row.avatar_url,
      isOnline: Boolean(row.is_online),
      lastSeen: row.last_seen ? new Date(row.last_seen).toISOString() : null,
      isVerified: Boolean(row.is_verified),
      role: row.role,
    }));

    return res.json({ members });
  }),
);

router.delete(
  '/:chatId/group/members/:memberId',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    const memberId = String(req.params.memberId ?? '').trim();
    if (!memberId) {
      throw new ApiError(400, 'memberId berilishi shart.');
    }

    const connection = await pool.getConnection();
    let participantIds = [];
    let removedUserId = '';
    let messagePayload = null;

    try {
      await connection.beginTransaction();
      await assertMembership(chatId, req.userId, connection);

      const [chatRows] = await connection.execute(
        'SELECT type, owner_id FROM chats WHERE id = ? LIMIT 1',
        [chatId],
      );
      if (chatRows.length === 0) {
        throw new ApiError(404, 'Chat topilmadi.');
      }
      const chat = chatRows[0];
      if (chat.type !== 'group') {
        throw new ApiError(400, 'Bu chat guruh emas.');
      }
      if (chat.owner_id !== req.userId) {
        throw new ApiError(403, "Faqat group owner a'zoni chiqara oladi.");
      }

      const [actorRows] = await connection.execute(
        'SELECT id, username, display_name FROM users WHERE id = ? LIMIT 1',
        [req.userId],
      );
      if (actorRows.length === 0) {
        throw new ApiError(404, 'Owner user topilmadi.');
      }
      const actor = actorRows[0];

      const [targetRows] = await connection.execute(
        `SELECT cm.user_id, cm.role, u.username, u.display_name
         FROM chat_members cm
         INNER JOIN users u ON u.id = cm.user_id
         WHERE cm.chat_id = ? AND cm.user_id = ?
         LIMIT 1`,
        [chatId, memberId],
      );
      if (targetRows.length === 0) {
        throw new ApiError(404, "Bu user guruhda topilmadi.");
      }
      const target = targetRows[0];
      if (target.role === 'owner') {
        throw new ApiError(400, 'Ownerni guruhdan chiqarib bo\'lmaydi.');
      }
      if (target.user_id === req.userId) {
        throw new ApiError(400, "O'zingizni bu route orqali chiqara olmaysiz.");
      }

      removedUserId = target.user_id;

      await connection.execute(
        'DELETE FROM chat_members WHERE chat_id = ? AND user_id = ? LIMIT 1',
        [chatId, memberId],
      );

      const eventText = buildGroupEventText({
        action: 'removed',
        actor,
        target: {
          id: target.user_id,
          username: target.username,
          display_name: target.display_name,
        },
      });
      const [insertResult] = await connection.execute(
        `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
         VALUES (?, ?, ?, 'text', NULL)`,
        [chatId, req.userId, eventText],
      );

      const summary = buildGroupEventSummary(
        'removed',
        actor,
        { display_name: target.display_name },
      );
      await connection.execute(
        `UPDATE chats
         SET last_message = ?,
             last_sender_id = ?,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = ?`,
        [summary, req.userId, chatId],
      );

      const [messageRows] = await connection.execute(
        `SELECT id, chat_id, sender_id, text, type, created_at, read_at
         FROM messages
         WHERE id = ?
         LIMIT 1`,
        [insertResult.insertId],
      );
      messagePayload = toMessage(messageRows[0]);

      const [memberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      participantIds = memberRows.map((row) => row.user_id);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const nowIso = new Date().toISOString();
    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:updated', {
          chatId,
          at: nowIso,
        });
        io.to(`user:${uid}`).emit('message:new', messagePayload);
      }
      io.to(`chat:${chatId}`).emit('message:new', messagePayload);

      if (removedUserId) {
        io.to(`user:${removedUserId}`).emit('chat:deleted', {
          chatId,
          at: nowIso,
        });
      }
    }

    return res.json({
      ok: true,
      message: 'A\'zo guruhdan chiqarildi.',
    });
  }),
);

router.get(
  '/:chatId/messages',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    await assertMembership(chatId, req.userId);

    const limitRaw = Number.parseInt(String(req.query.limit ?? '300'), 10);
    const limit = Number.isFinite(limitRaw) ? Math.min(Math.max(limitRaw, 1), 1000) : 300;

    const rows = await query(
      `SELECT id, chat_id, sender_id, text, type, created_at, read_at
       FROM messages
       WHERE chat_id = ?
       ORDER BY created_at ASC
       LIMIT ?`,
      [chatId, limit],
    );

    await markChatRead({
      chatId,
      userId: req.userId,
      io: req.app.locals.io,
    });

    res.json({ messages: rows.map(toMessage) });
  }),
);

router.post(
  '/:chatId/upload',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    const kind = String(req.body?.kind ?? '').trim().toLowerCase();
    const fileName = String(req.body?.fileName ?? '').trim();
    const mimeTypeFromBody = String(req.body?.mimeType ?? '').trim().toLowerCase();

    if (!allowedMediaKinds.has(kind)) {
      throw new ApiError(400, 'Media turi noto\'g\'ri.');
    }

    await assertMembership(chatId, req.userId);
    const permission = await resolveWritePermission(chatId, req.userId);
    assertWriteAllowed(permission);

    const parsed = parseBase64Input(req.body?.base64);
    const mimeType = parsed.mimeType || mimeTypeFromBody;
    const bytes = parsed.bytes;

    if (!bytes.length) {
      throw new ApiError(400, "Fayl bo'sh.");
    }
    if (bytes.length > 25 * 1024 * 1024) {
      throw new ApiError(413, 'Fayl 25MB dan kichik bo\'lishi kerak.');
    }

    const ext = resolveMediaExtension(kind, mimeType, fileName);
    await fs.mkdir(uploadsDir, { recursive: true });

    const fileKey = `${kind}-${chatId}-${Date.now()}-${randomUUID().slice(0, 8)}.${ext}`;
    await fs.writeFile(path.join(uploadsDir, fileKey), bytes);

    const host = `${req.protocol}://${req.get('host')}`;
    const url = `${host}/uploads/${fileKey}`;

    res.status(201).json({
      media: {
        kind,
        url,
        fileName: fileName || fileKey,
        mimeType,
        sizeBytes: bytes.length,
      },
    });
  }),
);

router.post(
  '/:chatId/messages',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    const text = String(req.body?.text ?? '').trim();
    const isStickerLegacy = Boolean(req.body?.isSticker);
    const requestedType = String(req.body?.type ?? '').trim().toLowerCase();
    let type = requestedType;

    if (!allowedMessageTypes.has(type)) {
      type = isStickerLegacy ? 'sticker' : 'text';
    }

    if (!text) {
      throw new ApiError(400, 'Xabar matni bo\'sh bo\'lmasligi kerak.');
    }

    const connection = await pool.getConnection();
    let messagePayload = null;
    let participantIds = [];

    try {
      await connection.beginTransaction();
      await assertMembership(chatId, req.userId, connection);

      const permission = await resolveWritePermission(chatId, req.userId, connection);
      assertWriteAllowed(permission);

      const [insertResult] = await connection.execute(
        `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
         VALUES (?, ?, ?, ?, ?)`,
        [chatId, req.userId, text, type, permission.isSaved ? new Date() : null],
      );

      await connection.execute(
        `UPDATE chats
         SET last_message = ?,
             last_sender_id = ?,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = ?`,
        [buildLastMessageSummary(type, text), req.userId, chatId],
      );

      const [messageRows] = await connection.execute(
        `SELECT id, chat_id, sender_id, text, type, created_at, read_at
         FROM messages
         WHERE id = ?
         LIMIT 1`,
        [insertResult.insertId],
      );

      const [memberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );

      messagePayload = toMessage(messageRows[0]);
      participantIds = memberRows.map((row) => row.user_id);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:updated', {
          chatId,
          at: new Date().toISOString(),
        });
        io.to(`user:${uid}`).emit('message:new', messagePayload);
      }
      io.to(`chat:${chatId}`).emit('message:new', messagePayload);
    }

    res.status(201).json({ message: messagePayload });
  }),
);

router.delete(
  '/:chatId/messages/:messageId',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    const messageId = Number.parseInt(String(req.params.messageId ?? ''), 10);
    if (!Number.isFinite(messageId) || messageId <= 0) {
      throw new ApiError(400, 'messageId noto\'g\'ri.');
    }

    const connection = await pool.getConnection();
    let participantIds = [];

    try {
      await connection.beginTransaction();
      await assertMembership(chatId, req.userId, connection);

      const [targetRows] = await connection.execute(
        `SELECT m.id, m.sender_id, c.is_saved
         FROM messages m
         INNER JOIN chats c ON c.id = m.chat_id
         WHERE m.id = ? AND m.chat_id = ?
         LIMIT 1`,
        [messageId, chatId],
      );
      if (targetRows.length === 0) {
        throw new ApiError(404, 'Xabar topilmadi.');
      }

      const target = targetRows[0];
      const isSavedChat = Boolean(target.is_saved);
      if (!isSavedChat && target.sender_id !== req.userId) {
        throw new ApiError(403, 'Faqat o\'z xabaringizni o\'chira olasiz.');
      }

      await connection.execute(
        'DELETE FROM messages WHERE id = ? AND chat_id = ? LIMIT 1',
        [messageId, chatId],
      );

      await refreshChatPreview(chatId, connection);

      const [memberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      participantIds = memberRows.map((row) => row.user_id);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:updated', {
          chatId,
          at: new Date().toISOString(),
        });
        io.to(`user:${uid}`).emit('message:deleted', {
          chatId,
          messageId: String(messageId),
        });
      }
      io.to(`chat:${chatId}`).emit('message:deleted', {
        chatId,
        messageId: String(messageId),
      });
    }

    res.json({ ok: true });
  }),
);

router.delete(
  '/:chatId',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;

    const connection = await pool.getConnection();
    let participantIds = [];

    try {
      await connection.beginTransaction();
      await assertMembership(chatId, req.userId, connection);

      const [chatRows] = await connection.execute(
        'SELECT is_saved, type, owner_id FROM chats WHERE id = ? LIMIT 1',
        [chatId],
      );
      if (chatRows.length === 0) {
        throw new ApiError(404, 'Chat topilmadi.');
      }
      if (Boolean(chatRows[0].is_saved)) {
        throw new ApiError(400, 'Saved chatni o\'chirib bo\'lmaydi.');
      }
      if (String(chatRows[0].type ?? '') === 'group' && chatRows[0].owner_id !== req.userId) {
        throw new ApiError(403, 'Groupni faqat owner o\'chira oladi.');
      }

      const [memberRows] = await connection.execute(
        'SELECT user_id FROM chat_members WHERE chat_id = ?',
        [chatId],
      );
      participantIds = memberRows.map((row) => row.user_id);

      await connection.execute('DELETE FROM chats WHERE id = ? LIMIT 1', [chatId]);

      await connection.commit();
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }

    const io = req.app.locals.io;
    if (io) {
      for (const uid of participantIds) {
        io.to(`user:${uid}`).emit('chat:deleted', {
          chatId,
          at: new Date().toISOString(),
        });
      }
      io.to(`chat:${chatId}`).emit('chat:deleted', {
        chatId,
        at: new Date().toISOString(),
      });
    }

    res.json({ ok: true });
  }),
);

router.post(
  '/:chatId/read',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const chatId = req.params.chatId;
    const result = await markChatRead({
      chatId,
      userId: req.userId,
      io: req.app.locals.io,
    });

    res.json({
      ok: true,
      readAt: result.readAt,
      updated: result.updatedCount,
    });
  }),
);

export default router;
