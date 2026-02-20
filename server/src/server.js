import http from 'node:http';
import path from 'node:path';

import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import { Server } from 'socket.io';

import { verifyToken } from './lib/auth.js';
import { config } from './lib/config.js';
import { pool, query } from './lib/db.js';
import { ApiError } from './lib/errors.js';
import { runMigrations } from './lib/migrations.js';
import authRoutes from './routes/auth.js';
import chatsRoutes from './routes/chats.js';
import usersRoutes from './routes/users.js';

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: config.corsOrigin,
    credentials: true,
  },
  transports: ['websocket', 'polling'],
});

app.locals.io = io;

app.use(
  helmet({
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: false,
    crossOriginEmbedderPolicy: false,
  }),
);
app.use(cors({ origin: config.corsOrigin, credentials: true }));
app.use(express.json({ limit: '35mb' }));
app.use(morgan('dev'));
app.use(
  '/uploads',
  express.static(path.resolve(process.cwd(), 'uploads'), {
    setHeaders: (res) => {
      // Web app (:8081) media fetch uchun cross-origin ruxsat.
      res.setHeader('Cross-Origin-Resource-Policy', 'cross-origin');
    },
  }),
);

app.get('/api/health', async (_req, res, next) => {
  try {
    await query('SELECT 1 AS ok');
    res.json({ ok: true, db: 'connected' });
  } catch (error) {
    next(error);
  }
});

app.use('/api/auth', authRoutes);
app.use('/api/users', usersRoutes);
app.use('/api/chats', chatsRoutes);

app.use((_req, _res, next) => {
  next(new ApiError(404, 'Route topilmadi.'));
});

app.use((error, _req, res, _next) => {
  const status = error.status ?? 500;
  const message = error.message ?? 'Server xatoligi.';

  if (status >= 500) {
    console.error(error);
  }

  res.status(status).json({
    error: {
      message,
      status,
      code: error.code ?? 'UNKNOWN',
    },
  });
});

const socketsByUser = new Map();

async function setPresence(userId, isOnline) {
  await query('UPDATE users SET is_online = ?, last_seen = NOW() WHERE id = ?', [
    isOnline ? 1 : 0,
    userId,
  ]);

  io.emit('presence:update', {
    userId,
    isOnline,
    lastSeen: new Date().toISOString(),
  });
}

io.use((socket, next) => {
  try {
    const token = socket.handshake.auth?.token ?? socket.handshake.query?.token;
    if (!token || typeof token !== 'string') {
      return next(new Error('Unauthorized'));
    }

    const payload = verifyToken(token);
    socket.userId = payload.sub;
    return next();
  } catch {
    return next(new Error('Unauthorized'));
  }
});

io.on('connection', async (socket) => {
  const userId = socket.userId;

  socket.join(`user:${userId}`);

  const existingSet = socketsByUser.get(userId) ?? new Set();
  existingSet.add(socket.id);
  socketsByUser.set(userId, existingSet);

  if (existingSet.size === 1) {
    await setPresence(userId, true).catch(() => {});
  }

  socket.on('chat:join', async ({ chatId } = {}) => {
    if (!chatId || typeof chatId !== 'string') return;

    try {
      const [rows] = await pool.execute(
        'SELECT 1 FROM chat_members WHERE chat_id = ? AND user_id = ? LIMIT 1',
        [chatId, userId],
      );

      if (rows.length > 0) {
        socket.join(`chat:${chatId}`);
      }
    } catch {
      // ignored
    }
  });

  socket.on('chat:leave', ({ chatId } = {}) => {
    if (!chatId || typeof chatId !== 'string') return;
    socket.leave(`chat:${chatId}`);
  });

  socket.on('presence:set', async ({ isOnline } = {}) => {
    const online = Boolean(isOnline);
    await setPresence(userId, online).catch(() => {});
  });

  socket.on('disconnect', async () => {
    const set = socketsByUser.get(userId);
    if (!set) return;

    set.delete(socket.id);
    if (set.size > 0) return;

    socketsByUser.delete(userId);
    await setPresence(userId, false).catch(() => {});
  });
});

async function startServer() {
  await runMigrations();
  server.listen(config.port, () => {
    console.log(`Bekgram server running on http://localhost:${config.port}`);
  });
}

startServer().catch((error) => {
  console.error('Server startup failed:', error);
  process.exit(1);
});
