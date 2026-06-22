const fs = require('fs');
const { Pool } = require('pg');
require('dotenv').config();

// ตั้งค่าเชื่อมต่อฐานข้อมูล (ใช้ค่าเดียวกับใน server.js)
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'Wit03072003', // รหัสผ่านของคุณ
  database: process.env.DB_NAME || 'geohealth',
});

async function importCSV() {
  console.log('⏳ กำลังอ่านไฟล์ diseases.csv...');
  
  try {
    const csvData = fs.readFileSync('./data/diseases.csv', 'utf8');
    const lines = csvData.split('\n');
    let importedCount = 0;

    for (let i = 1; i < lines.length; i++) { // ข้ามบรรทัดแรก (Header)
      const line = lines[i].trim();
      if (!line) continue;

      // แยกคอลัมน์ด้วยลูกน้ำ (,)
      const parts = line.split(',');
      let code = parts[0].trim();
      let name = parts.slice(1).join(',').trim(); // เผื่อชื่อโรคมีลูกน้ำผสมอยู่

      // ถ้ามีรหัสโรค และมีชื่อโรค (ข้ามบรรทัดที่เป็นหัวข้อกลุ่มโรค)
      if (code && name && code !== 'รหัส_506') {
        // เติม 0 ข้างหน้ารหัสที่เป็นเลขตัวเดียว (เช่น 1 -> 01)
        if (code.length === 1 && !isNaN(code)) {
          code = '0' + code;
        }

        await pool.query(
          `INSERT INTO master_disease (code, name_th, is_notifiable)
           VALUES ($1, $2, true)
           ON CONFLICT (code) DO UPDATE SET name_th = EXCLUDED.name_th`,
          [code, name]
        );
        importedCount++;
        console.log(`✅ นำเข้า: [${code}] ${name}`);
      }
    }
    console.log(`\n🎉 นำเข้าข้อมูลสำเร็จทั้งหมด ${importedCount} โรค!`);
  } catch (error) {
    console.error('❌ เกิดข้อผิดพลาด:', error.message);
  } finally {
    await pool.end();
  }
}

importCSV();