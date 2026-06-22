const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');
require('dotenv').config();

const baseConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || '',
};

const defaultDb = process.env.DB_DEFAULT_DATABASE || 'postgres';
const targetDb = process.env.DB_NAME || 'geohealth';

async function main() {
  const adminPool = new Pool({ ...baseConfig, database: defaultDb });
  try {
    const exists = await adminPool.query('SELECT 1 FROM pg_database WHERE datname = $1', [targetDb]);
    if (exists.rowCount === 0) {
      console.log('Creating database', targetDb);
      await adminPool.query(`CREATE DATABASE ${targetDb}`);
    } else {
      console.log('Database exists', targetDb);
    }
  } finally {
    await adminPool.end();
  }

  const dbPool = new Pool({ ...baseConfig, database: targetDb });
  try {
    console.log('Creating users table if needed');
    await dbPool.query(`CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      username TEXT UNIQUE NOT NULL,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      name_th TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'volunteer',
      is_active BOOLEAN NOT NULL DEFAULT true,
      last_login_at TIMESTAMP
    );`);
    console.log('Users table ready');
  } finally {
    await dbPool.end();
  }
}

main().catch((err) => {
  console.error('init-db-simple failed', err.code, err.message);
  process.exit(1);
});
