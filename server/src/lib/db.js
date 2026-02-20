import mysql from 'mysql2/promise';

import { config } from './config.js';

export const pool = mysql.createPool({
  host: config.db.host,
  port: config.db.port,
  user: config.db.user,
  password: config.db.password,
  database: config.db.database,
  waitForConnections: true,
  connectionLimit: 12,
  queueLimit: 0,
  timezone: 'Z',
});

export async function query(sql, params = []) {
  const [rows] = await pool.execute(sql, params);
  return rows;
}
