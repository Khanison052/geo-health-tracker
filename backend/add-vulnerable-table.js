const { Pool } = require('pg');
require('dotenv').config();
const pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || 'Wit03072003', // รหัสผ่านของคุณ
    database: process.env.DB_NAME || 'geohealth',
});

async function createTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS vulnerable_groups (
        id SERIAL PRIMARY KEY,
        name_th TEXT NOT NULL,
        type TEXT NOT NULL,
        lat DOUBLE PRECISION,
        lng DOUBLE PRECISION,
        address_detail TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
  `);
  console.log('✅ สร้างตาราง vulnerable_groups สำเร็จ');
  await pool.end();
}
createTable();