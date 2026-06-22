const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'Wit03072003', // รหัสผ่านของคุณ
  database: process.env.DB_NAME || 'geohealth',
});

async function addColumn() {
  try {
    // สั่งเพิ่มคอลัมน์ address_detail ลงในตาราง patients
    await pool.query(`ALTER TABLE patients ADD COLUMN IF NOT EXISTS address_detail TEXT;`);
    console.log('✅ เพิ่มคอลัมน์ address_detail ในฐานข้อมูลสำเร็จแล้ว!');
  } catch (err) {
    console.error('❌ เกิดข้อผิดพลาด:', err.message);
  } finally {
    await pool.end();
  }
}

addColumn();