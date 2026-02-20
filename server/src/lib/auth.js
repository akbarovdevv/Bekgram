import jwt from 'jsonwebtoken';

import { config } from './config.js';
import { ApiError } from './errors.js';

export function createToken(userId) {
  return jwt.sign({ sub: userId }, config.jwtSecret, {
    expiresIn: config.jwtExpiresIn,
  });
}

export function verifyToken(token) {
  try {
    const payload = jwt.verify(token, config.jwtSecret);
    return payload;
  } catch {
    throw new ApiError(401, 'Token yaroqsiz yoki muddati tugagan.');
  }
}

export function authMiddleware(req, _res, next) {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    return next(new ApiError(401, 'Autorizatsiya talab qilinadi.'));
  }

  const token = header.slice(7).trim();
  const payload = verifyToken(token);
  req.userId = payload.sub;
  req.token = token;
  return next();
}
