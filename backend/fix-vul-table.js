const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'Wit03072003', // รหัสผ่านของคุณ
  database: process.env.DB_NAME || 'geohealth',
});

async function fixTable() {
  try {
    console.log('กำลังอัปเดตตาราง vulnerable_groups...');
    
    // สั่งบังคับเพิ่มคอลัมน์ที่ขาดหายไป
    await pool.query(`
      ALTER TABLE vulnerable_groups 
      ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION,
      ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION,
      ADD COLUMN IF NOT EXISTS address_detail TEXT;
    `);
    
    console.log('✅ เพิ่มคอลัมน์ lat, lng, address_detail สำเร็จแล้ว!');
  } catch (err) {
    console.error('❌ เกิดข้อผิดพลาด:', err.message);
  } finally {
    await pool.end();
  }
}

fixTable();