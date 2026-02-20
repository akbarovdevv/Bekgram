import dotenv from 'dotenv';

dotenv.config();

export const config = {
  port: Number(process.env.PORT ?? 3000),
  corsOrigin: process.env.CORS_ORIGIN ?? '*',
  db: {
    host: process.env.DB_HOST ?? '127.0.0.1',
    port: Number(process.env.DB_PORT ?? 3306),
    user: process.env.DB_USER ?? 'bekgram_app',
    password: process.env.DB_PASSWORD ?? 'Bekgram@2026',
    database: process.env.DB_NAME ?? 'bekgram_local',
  },
  jwtSecret: process.env.JWT_SECRET ?? 'change_this_secret_now',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN ?? '7d',
};
