import { randomUUID } from 'node:crypto';

import express from 'express';

import { authMiddleware } from '../lib/auth.js';
import { pool, query } from '../lib/db.js';
import { ApiError, asyncHandler } from '../lib/errors.js';
import { toMessage, toUser } from '../lib/serializers.js';

const router = express.Router();

const verificationAdmins = new Set(['asilbek', 'verify']);
const verificationCooldownDays = 7;

function normalizeUsername(username) {
  return String(username ?? '').trim().toLowerCase().replaceAll(' ', '');
}

function isVerificationAdminUsername(usernameLower) {
  return verificationAdmins.has(String(usernameLower ?? '').trim().toLowerCase());
}

function buildDirectKey(userA, userB) {
  const sorted = [userA, userB].sort();
  return `direct:${sorted[0]}_${sorted[1]}`;
}

async function getOrCreateDirectChat(connection, userA, userB) {
  const directKey = buildDirectKey(userA, userB);
  const [existingRows] = await connection.execute(
    'SELECT id FROM chats WHERE direct_key = ? LIMIT 1',
    [directKey],
  );
  if (existingRows.length > 0) {
    return existingRows[0].id;
  }

  const chatId = randomUUID();
  try {
    await connection.execute(
      `INSERT INTO chats (id, type, direct_key, is_saved, last_message, last_sender_id, last_message_at)
       VALUES (?, 'direct', ?, 0, NULL, NULL, NULL)`,
      [chatId, directKey],
    );
    await connection.execute(
      'INSERT INTO chat_members (chat_id, user_id, role) VALUES (?, ?, ?), (?, ?, ?)',
      [chatId, userA, 'member', chatId, userB, 'member'],
    );
    return chatId;
  } catch (error) {
    if (error?.code !== 'ER_DUP_ENTRY') throw error;
    const [fallbackRows] = await connection.execute(
      'SELECT id FROM chats WHERE direct_key = ? LIMIT 1',
      [directKey],
    );
    if (fallbackRows.length > 0) {
      return fallbackRows[0].id;
    }
    throw error;
  }
}

function buildVerificationRequestText(requester, requestedAtIso) {
  return JSON.stringify({
    kind: 'verify_request',
    requesterId: requester.id,
    username: requester.username,
    displayName: requester.display_name,
    bio: requester.bio ?? '',
    phoneNumber: requester.phone_number ?? null,
    requestedAt: requestedAtIso,
  });
}

function buildVerificationDecisionText({
  requester,
  reviewer,
  approved,
  blockedUntilIso,
  decidedAtIso,
}) {
  return JSON.stringify({
    kind: 'verify_decision',
    requesterId: requester.id,
    username: requester.username,
    reviewerId: reviewer.id,
    reviewerUsername: reviewer.username,
    approved,
    blockedUntil: blockedUntilIso,
    decidedAt: decidedAtIso,
  });
}

function buildDecisionMessage(approved, usernameLower, blockedUntilIso) {
  if (approved) {
    return `@${usernameLower} verified qilindi.`;
  }
  return `@${usernameLower} so'rovi rad etildi. Qayta yuborish: ${blockedUntilIso}`;
}

async function emitChatMessage({ app, chatId, participantIds, messagePayload }) {
  const io = app.locals.io;
  if (!io) return;

  for (const uid of participantIds) {
    io.to(`user:${uid}`).emit('chat:updated', {
      chatId,
      at: new Date().toISOString(),
    });
    io.to(`user:${uid}`).emit('message:new', messagePayload);
  }
  io.to(`chat:${chatId}`).emit('message:new', messagePayload);
}

router.get(
  '/search',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const q = String(req.query.q ?? '').trim().toLowerCase();
    if (!q) {
      return res.json({ users: [] });
    }

    const rows = await query(
      `SELECT *
       FROM users
       WHERE username_lower LIKE ?
         AND id <> ?
       ORDER BY username_lower ASC
       LIMIT 30`,
      [`${q}%`, req.userId],
    );

    return res.json({ users: rows.map(toUser) });
  }),
);

router.put(
  '/verify',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const usernameLower = normalizeUsername(req.body?.username);
    const isVerified = Boolean(req.body?.isVerified);

    if (!/^[a-z0-9_]{4,24}$/.test(usernameLower)) {
      throw new ApiError(400, "Username 4-24 ta: a-z, 0-9 yoki _ bo'lishi kerak.");
    }

    const currentRows = await query('SELECT username_lower FROM users WHERE id = ? LIMIT 1', [
      req.userId,
    ]);
    if (currentRows.length === 0) {
      throw new ApiError(404, 'Foydalanuvchi topilmadi.');
    }

    const currentUsernameLower = currentRows[0].username_lower;
    if (!isVerificationAdminUsername(currentUsernameLower)) {
      throw new ApiError(403, 'Faqat @asilbek yoki @verify verificationni boshqara oladi.');
    }

    const targetRows = await query('SELECT * FROM users WHERE username_lower = ? LIMIT 1', [
      usernameLower,
    ]);
    if (targetRows.length === 0) {
      throw new ApiError(404, `@${usernameLower} topilmadi.`);
    }

    await query(
      `UPDATE users
       SET is_verified = ?,
           verify_request_blocked_until = CASE WHEN ? = 1 THEN NULL ELSE verify_request_blocked_until END,
           updated_at = NOW()
       WHERE username_lower = ?`,
      [isVerified ? 1 : 0, isVerified ? 1 : 0, usernameLower],
    );

    const refreshedRows = await query('SELECT * FROM users WHERE username_lower = ? LIMIT 1', [
      usernameLower,
    ]);
    const updatedUser = refreshedRows[0];

    req.app.locals.io?.emit('presence:update', {
      userId: updatedUser.id,
      isOnline: Boolean(updatedUser.is_online),
      lastSeen: new Date(updatedUser.last_seen ?? Date.now()).toISOString(),
    });

    return res.json({
      user: toUser(updatedUser),
      message: isVerified
        ? `@${usernameLower} verified qilindi.`
        : `@${usernameLower} verification olib tashlandi.`,
    });
  }),
);

router.post(
  '/verification/request',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const connection = await pool.getConnection();
    let chatId = '';
    let reviewerId = '';
    let participantIds = [];
    let messagePayload = null;

    try {
      await connection.beginTransaction();

      const [requesterRows] = await connection.execute(
        'SELECT * FROM users WHERE id = ? LIMIT 1',
        [req.userId],
      );
      if (requesterRows.length === 0) {
        throw new ApiError(404, 'Foydalanuvchi topilmadi.');
      }
      const requester = requesterRows[0];

      if (isVerificationAdminUsername(requester.username_lower)) {
        throw new ApiError(400, 'Admin akkaunt verification so\'rovi yubormaydi.');
      }

      const blockedUntilRaw = requester.verify_request_blocked_until;
      const blockedUntil = blockedUntilRaw ? new Date(blockedUntilRaw) : null;
      if (blockedUntil && blockedUntil.getTime() > Date.now()) {
        throw new ApiError(
          429,
          `So'rov rad etilgan. Qayta yuborish: ${blockedUntil.toISOString()}`,
        );
      }

      const [reviewerRows] = await connection.execute(
        `SELECT *
         FROM users
         WHERE username_lower IN ('verify', 'asilbek')
         ORDER BY FIELD(username_lower, 'verify', 'asilbek')
         LIMIT 1`,
      );
      if (reviewerRows.length === 0) {
        throw new ApiError(404, '@verify akkaunti topilmadi.');
      }
      const reviewer = reviewerRows[0];
      reviewerId = reviewer.id;

      if (reviewerId === req.userId) {
        throw new ApiError(400, 'O\'zingizga verification so\'rovi yubora olmaysiz.');
      }

      chatId = await getOrCreateDirectChat(connection, req.userId, reviewerId);

      const requestedAtIso = new Date().toISOString();
      const requestText = buildVerificationRequestText(requester, requestedAtIso);

      const [insertResult] = await connection.execute(
        `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
         VALUES (?, ?, ?, 'text', NULL)`,
        [chatId, req.userId, requestText],
      );

      await connection.execute(
        `UPDATE chats
         SET last_message = ?,
             last_sender_id = ?,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = ?`,
        ['Verification request', req.userId, chatId],
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

    await emitChatMessage({
      app: req.app,
      chatId,
      participantIds,
      messagePayload,
    });

    res.status(201).json({
      chatId,
      reviewerId,
      message: 'Verification so\'rovi yuborildi.',
    });
  }),
);

router.post(
  '/verification/decision',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const requesterId = String(req.body?.requesterId ?? '').trim();
    const approved = req.body?.approve == true;

    if (!requesterId) {
      throw new ApiError(400, 'requesterId berilishi shart.');
    }
    if (requesterId === req.userId) {
      throw new ApiError(400, 'O\'zingizga decision bera olmaysiz.');
    }

    const connection = await pool.getConnection();
    let reviewer = null;
    let requester = null;
    let updatedRequester = null;
    let blockedUntilIso = null;
    let chatId = '';
    let participantIds = [];
    let messagePayload = null;

    try {
      await connection.beginTransaction();

      const [reviewerRows] = await connection.execute(
        'SELECT * FROM users WHERE id = ? LIMIT 1',
        [req.userId],
      );
      if (reviewerRows.length === 0) {
        throw new ApiError(404, 'Reviewer topilmadi.');
      }
      reviewer = reviewerRows[0];
      if (!isVerificationAdminUsername(reviewer.username_lower)) {
        throw new ApiError(403, 'Faqat @asilbek yoki @verify decision bera oladi.');
      }

      const [requesterRows] = await connection.execute(
        'SELECT * FROM users WHERE id = ? LIMIT 1',
        [requesterId],
      );
      if (requesterRows.length === 0) {
        throw new ApiError(404, 'So\'rov yuborgan user topilmadi.');
      }
      requester = requesterRows[0];

      if (approved) {
        await connection.execute(
          `UPDATE users
           SET is_verified = 1,
               verify_request_blocked_until = NULL,
               updated_at = NOW()
           WHERE id = ?`,
          [requesterId],
        );
      } else {
        const blockedUntil = new Date(Date.now() + verificationCooldownDays * 24 * 60 * 60 * 1000);
        blockedUntilIso = blockedUntil.toISOString();
        await connection.execute(
          `UPDATE users
           SET verify_request_blocked_until = ?,
               updated_at = NOW()
           WHERE id = ?`,
          [blockedUntilIso.slice(0, 19).replace('T', ' '), requesterId],
        );
      }

      const [updatedRows] = await connection.execute(
        'SELECT * FROM users WHERE id = ? LIMIT 1',
        [requesterId],
      );
      updatedRequester = updatedRows[0];

      chatId = await getOrCreateDirectChat(connection, req.userId, requesterId);
      const decidedAtIso = new Date().toISOString();
      const decisionText = buildVerificationDecisionText({
        requester,
        reviewer,
        approved,
        blockedUntilIso,
        decidedAtIso,
      });

      const [insertResult] = await connection.execute(
        `INSERT INTO messages (chat_id, sender_id, text, type, read_at)
         VALUES (?, ?, ?, 'text', NULL)`,
        [chatId, req.userId, decisionText],
      );

      await connection.execute(
        `UPDATE chats
         SET last_message = ?,
             last_sender_id = ?,
             last_message_at = NOW(),
             updated_at = NOW()
         WHERE id = ?`,
        [approved ? 'Verification approved' : 'Verification rejected', req.userId, chatId],
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

    req.app.locals.io?.emit('presence:update', {
      userId: updatedRequester.id,
      isOnline: Boolean(updatedRequester.is_online),
      lastSeen: new Date(updatedRequester.last_seen ?? Date.now()).toISOString(),
    });

    await emitChatMessage({
      app: req.app,
      chatId,
      participantIds,
      messagePayload,
    });

    return res.json({
      user: toUser(updatedRequester),
      blockedUntil: blockedUntilIso,
      message: buildDecisionMessage(
        approved,
        updatedRequester.username_lower,
        blockedUntilIso ?? 'n/a',
      ),
    });
  }),
);

router.get(
  '/:id',
  authMiddleware,
  asyncHandler(async (req, res) => {
    const rows = await query('SELECT * FROM users WHERE id = ? LIMIT 1', [req.params.id]);
    if (rows.length === 0) {
      throw new ApiError(404, 'User topilmadi.');
    }

    res.json({ user: toUser(rows[0]) });
  }),
);

export default router;
