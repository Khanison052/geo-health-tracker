/**
 * Geo-Health Tracker — Backend API
 * Stack: Node.js + Express + PostgreSQL/PostGIS
 */

require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
const bcrypt = require('bcrypt');
const jwt = require('jsonwebtoken');
const axios = require('axios');
const XLSX = require('xlsx'); // 🌟 เพิ่มบรรทัดนี้ไว้ด้านบนสุดคู่กับพวก express, cors

const app = express();
app.use(cors());
app.use(express.json());

const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-key-change-in-production';
const TOKEN_EXPIRY = '7d';

// ตั้งค่าการเชื่อมต่อฐานข้อมูล
const dbUser = (process.env.DB_USER || 'postgres').trim();
const dbHost = (process.env.DB_HOST || 'localhost').trim();
const dbPassword = (process.env.DB_PASSWORD || 'postgres').trim();
const dbName = (process.env.DB_NAME || 'postgres').trim();
const dbPort = parseInt(process.env.DB_PORT || '5432', 10);

console.log(`🔌 กำลังเชื่อมต่อฐานข้อมูลที่: ${dbHost}`);
console.log(`👤 ใช้ชื่อผู้ใช้งาน (User): "${dbUser}"`);

const pool = new Pool({
  user: dbUser,
  host: dbHost,
  database: dbName,
  password: dbPassword,
  port: dbPort,
  ssl: { rejectUnauthorized: false }
});

pool.on('error', (err) => {
  console.error('Unexpected database error', err);
});

// ฟังก์ชันสำหรับส่งข้อความเข้า LINE
async function sendLineAlert(message) {
  const token = process.env.LINE_ACCESS_TOKEN;
  const targetId = process.env.LINE_TARGET_ID;

  if (!token || !targetId) {
    console.log('⚠️ ไม่ได้ตั้งค่า LINE_ACCESS_TOKEN หรือ LINE_TARGET_ID ใน .env');
    return;
  }

  try {
    await axios.post(
      'https://api.line.me/v2/bot/message/push',
      { to: targetId, messages: [{ type: 'text', text: message }] },
      { headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` } }
    );
    console.log('✅ ส่งแจ้งเตือนเข้า LINE สำเร็จ!');
  } catch (error) {
    console.error('❌ ส่งแจ้งเตือน LINE พลาด:', error.response ? error.response.data : error.message);
  }
}

// Authentication Middleware
async function verifyToken(req, res, next) {
  const token = req.headers.authorization?.split(' ')[1];
  if (!token) return res.status(401).json({ error: 'ต้องระบุ token' });
  try {
    const decoded = jwt.verify(token, JWT_SECRET);
    req.userId = decoded.userId;
    req.userRole = decoded.role;
    next();
  } catch (error) {
    res.status(401).json({ error: 'Token ไม่ถูกต้อง' });
  }
}

function parseInteger(value, fallback) {
  const parsed = parseInt(value, 10);
  return Number.isNaN(parsed) ? fallback : parsed;
}

function parseFloatOrNull(value) {
  const parsed = parseFloat(value);
  return Number.isNaN(parsed) ? null : parsed;
}

app.get('/api/health', async (req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', mode: 'production', timestamp: new Date().toISOString() });
  } catch (error) {
    res.status(500).json({ status: 'error', message: 'Database connection failed', error: error.message });
  }
});

// ─── AUTHENTICATION ───

app.post('/api/auth/register', async (req, res) => {
  try {
    const { username, email, password, name_th, hospital, health_region, province, district, subdistrict, role = 'volunteer' } = req.body;
    if (!username || !email || !password || !name_th) return res.status(400).json({ error: 'กรุณากรอกข้อมูลหลักให้ครบถ้วน' });

    const existingUser = await pool.query('SELECT id FROM users WHERE username = $1 OR email = $2', [username, email]);
    if (existingUser.rowCount > 0) return res.status(400).json({ error: 'ผู้ใช้นี้มีอยู่แล้วในระบบ' });

    const passwordHash = await bcrypt.hash(password, 10);
    const result = await pool.query(
      `INSERT INTO users (username, email, password_hash, name_th, role, hospital, health_region, province, district, subdistrict)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id, username, email, name_th, role`,
      [username, email, passwordHash, name_th, role, hospital, health_region, province, district, subdistrict]
    );

    await pool.query('UPDATE master_volunteer SET is_registered = TRUE WHERE id_card = $1', [username]);

    res.status(201).json({ message: 'สมัครสมาชิกสำเร็จ', user: result.rows[0] });
  } catch (error) {
    console.error('POST /api/auth/register', error);
    res.status(500).json({ error: 'ไม่สามารถสมัครสมาชิกได้' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    if (!username || !password) return res.status(400).json({ error: 'กรุณากรอก username และ password' });

    const result = await pool.query(
      'SELECT id, username, email, name_th, role, password_hash, hospital, health_region, province, district, subdistrict FROM users WHERE username = $1 AND is_active = true',
      [username]
    );
    if (result.rowCount === 0) return res.status(401).json({ error: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });

    const user = result.rows[0];
    const isPasswordValid = await bcrypt.compare(password, user.password_hash);
    if (!isPasswordValid) return res.status(401).json({ error: 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง' });

    await pool.query('UPDATE users SET last_login_at = NOW() WHERE id = $1', [user.id]);
    const token = jwt.sign({ userId: user.id, username: user.username, role: user.role }, JWT_SECRET, { expiresIn: TOKEN_EXPIRY });

    res.json({
      message: 'เข้าสู่ระบบสำเร็จ',
      token,
      user: {
        id: user.id, username: user.username, email: user.email, name_th: user.name_th, role: user.role,
        hospital: user.hospital, health_region: user.health_region, province: user.province, district: user.district, subdistrict: user.subdistrict
      },
    });
  } catch (error) {
    console.error('POST /api/auth/login', error);
    res.status(500).json({ error: 'ไม่สามารถเข้าสู่ระบบได้' });
  }
});

app.get('/api/auth/verify', verifyToken, async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, username, email, name_th, role, hospital, health_region, province, district, subdistrict FROM users WHERE id = $1 AND is_active = true',
      [req.userId]
    );
    if (result.rowCount === 0) return res.status(401).json({ error: 'ไม่พบผู้ใช้' });
    res.json({ valid: true, user: result.rows[0] });
  } catch (error) {
    console.error('GET /api/auth/verify', error);
    res.status(500).json({ error: 'ไม่สามารถตรวจสอบ token ได้' });
  }
});

// ─── DISEASES & VULNERABLE ───

app.get('/api/diseases', async (req, res) => {
  try {
    const { code, q } = req.query;
    const values = [];
    const filters = [];

    if (code) { values.push(code); filters.push(`(group_code = $${values.length} OR code = $${values.length})`); }
    if (q) { values.push(`%${String(q).toLowerCase()}%`); filters.push(`(LOWER(name_th) LIKE $${values.length} OR LOWER(code) LIKE $${values.length})`); }

    const whereClause = filters.length ? `WHERE ${filters.join(' AND ')}` : '';
    const result = await pool.query(`SELECT code, group_code AS group, name_th AS name, icd10 FROM master_disease ${whereClause} ORDER BY name_th LIMIT 200`, values);
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: 'ไม่สามารถดึงรายการโรคได้' });
  }
});

app.get('/api/vulnerable', verifyToken, async (req, res) => { // 🌟 1. ใส่ verifyToken
  try {
    const userId = req.userId;
    const userRole = req.userRole;

    let queryStr = "";
    let queryParams = [];

    // 🌟 2. ดักจับสิทธิ์
    if (userRole === 'admin' || userRole === 'executive' || userRole === 'hospital' || userRole === 'staff') {
      // ผู้บริหาร และ รพ.สต. ให้เห็นกลุ่มเปราะบางทั้งหมด
      queryStr = 'SELECT * FROM vulnerable_groups ORDER BY id DESC';
    } else {
      // อสม. เห็นแค่กลุ่มเปราะบางที่ตัวเองรายงาน
      queryStr = 'SELECT * FROM vulnerable_groups WHERE reporter_id = $1 ORDER BY id DESC';
      queryParams.push(userId);
    }

    const result = await pool.query(queryStr, queryParams);
    res.json({ data: result.rows });
  } catch (error) {
    res.status(500).json({ error: 'ไม่สามารถดึงข้อมูลกลุ่มเปราะบางได้' });
  }
});

app.post('/api/vulnerable', verifyToken, async (req, res) => {
  try {
    const { name, type, lat, lng, address } = req.body;
    const reporterId = req.userId;

    await pool.query(
      `INSERT INTO vulnerable_groups (name_th, type, lat, lng, address_detail, location, reporter_id) 
       VALUES ($1, $2, $3, $4, $5, ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography, $6)`, // 🌟 3. เพิ่ม $6
      [name, type, lat, lng, address, reporterId] // 🌟 4. ส่ง reporterId เข้าไป
    );

    const alertMsg = `📌 เพิ่มข้อมูลกลุ่มเปราะบางใหม่: ${name}\nประเภท: ${type}\nพิกัด: ${address || 'ไม่ระบุ'}`;
    await pool.query(
      `INSERT INTO line_alerts (channel_id, message, status, reporter_id) VALUES ('system', $1, 'sent', $2)`, 
      [alertMsg, reporterId]
    );
    await sendLineAlert(alertMsg);

    res.status(201).json({ message: 'บันทึกและแจ้งเตือนสำเร็จ' });
  } catch (error) {
    res.status(500).json({ error: 'ไม่สามารถบันทึกข้อมูลได้' });
  }
});

// ─── PATIENTS (REPORTING) ───

// 🌟 แก้ไข: ดึงข้อมูลโดยมีการเช็คสิทธิ์ (RBAC) กรองข้อมูลตาม Role ของผู้ใช้งาน
app.get('/api/patients', verifyToken, async (req, res) => { // ⚠️ สำคัญมาก: ใส่ verifyToken ตรงนี้
  try {
    const userId = req.userId;
    const userRole = req.userRole;

    let filterPatients = "";
    let filterMentalPsy = "";
    let queryParams = [];

    // 🌟 กำหนดเงื่อนไขการมองเห็น (RBAC)
    if (userRole === 'admin' || userRole === 'executive') {
      // ผู้บริหาร: เห็นทั้งหมด
      filterPatients = "WHERE lat IS NOT NULL AND lng IS NOT NULL";
      filterMentalPsy = "WHERE location IS NOT NULL";
    } 
    else if (userRole === 'hospital' || userRole === 'staff') {
      // รพ.สต.: เห็นทั้งหมด (ถ้าจะให้เห็นแค่ รพ.สต. ของตัวเอง ต้องอิงจากค่า hospital ใน db เพิ่มเติมครับ)
      // เบื้องต้นให้เห็นทั้งหมดเหมือนผู้บริหารก่อนครับ
      filterPatients = "WHERE lat IS NOT NULL AND lng IS NOT NULL";
      filterMentalPsy = "WHERE location IS NOT NULL";
    } 
    else {
      // อสม. (volunteer): เห็นแค่ของตัวเองเท่านั้น
      filterPatients = "WHERE lat IS NOT NULL AND lng IS NOT NULL AND reporter_id = $1";
      filterMentalPsy = "WHERE location IS NOT NULL AND reporter_id = $1";
      queryParams.push(userId);
    }

    // 1. ตารางผู้ป่วย 506
    const patientsResult = await pool.query(`
      SELECT 
        id, name_th AS name, disease_code, disease_name, 
        lat, lng, 
        village_name AS village, severity, report_date
      FROM vw_patients_full
      ${filterPatients}
    `, queryParams);

    // 2. ตารางสุขภาพจิต
    const mentalResult = await pool.query(`
      SELECT 
        id, name_th AS name, 'MH' AS disease_code, target_group AS disease_name, 
        ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng, 
        address_detail AS village, risk_level AS severity, report_date
      FROM mental_screenings
      ${filterMentalPsy}
    `, queryParams);

    // 3. ตารางจิตเวช
    const psychiatricResult = await pool.query(`
      SELECT 
        id, name_th AS name, 'PSY' AS disease_code, psychiatric_group AS disease_name, 
        ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng, 
        address_detail AS village, follow_up_status AS severity, report_date
      FROM psychiatric_patients
      ${filterMentalPsy}
    `, queryParams);

    // 🌟 นำ Array ของทั้ง 3 ตารางมารวมกัน
    let combinedData = [
      ...patientsResult.rows,
      ...mentalResult.rows,
      ...psychiatricResult.rows
    ];

    console.log(`✅ ดึงข้อมูลสำเร็จ! (Role: ${userRole}, ID: ${userId}) 506: ${patientsResult.rows.length} | MH: ${mentalResult.rows.length} | PSY: ${psychiatricResult.rows.length} | รวมทั้งหมด: ${combinedData.length}`);

    // เรียงลำดับข้อมูลใหม่ตามวันที่
    combinedData.sort((a, b) => new Date(b.report_date) - new Date(a.report_date));

    // จำกัดลิมิตข้อมูล
    if (combinedData.length > 1000) {
      combinedData = combinedData.slice(0, 1000);
    }

    res.json({ count: combinedData.length, data: combinedData });
  } catch (error) {
    console.error('GET /api/patients error:', error.message);
    res.status(500).json({ error: 'ไม่สามารถดึงข้อมูลผู้ป่วยรวมได้', details: error.message });
  }
});

app.post('/api/patients', verifyToken, async (req, res) => {
  try {
    const { name, disease_code, lat, lng, address, severity = 'mild', age, gender, nationality, occupation, onset_date, date_of_death } = req.body;
    const reporterId = req.userId;

    if (!name || !disease_code || lat == null || lng == null) return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });

    const diseaseResult = await pool.query('SELECT name_th FROM master_disease WHERE code = $1', [disease_code]);
    if (diseaseResult.rowCount === 0) return res.status(400).json({ error: `ไม่พบรหัสโรค ${disease_code}` });

    let village_id = null;
    let house_number = ''; 

    if (address) {
      const { village, tambon, amphoe, province, house_number: reqHouseNum } = address;
      house_number = reqHouseNum || ''; 
      const villageName = (village && village !== '-') ? village : tambon;

      const findVillage = await pool.query('SELECT id FROM villages WHERE name_th = $1 AND province = $2 LIMIT 1', [villageName, province]);
      if (findVillage.rowCount > 0) {
        village_id = findVillage.rows[0].id;
      } else {
        const newVillage = await pool.query(
          `INSERT INTO villages (moo, name_th, tambon, amphoe, province, center) VALUES (0, $1, $2, $3, $4, ST_SetSRID(ST_MakePoint($5, $6), 4326)::geography) RETURNING id`,
          [villageName, tambon, amphoe, province, parseFloat(lng), parseFloat(lat)]
        );
        village_id = newVillage.rows[0].id;
      }
    } else {
      village_id = 3; // Fallback
    }

    const insertResult = await pool.query(
      `INSERT INTO patients (
         name_th, disease_code, location, village_id, severity, report_date, address_detail,
         age, gender, nationality, occupation, onset_date, date_of_death,
         reporter_id -- 🌟 2. เพิ่มคอลัมน์ reporter_id ในคำสั่ง INSERT
       ) VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5, $6, CURRENT_DATE, $7, $8, $9, $10, $11, $12, $13, $14) RETURNING id`,
      [name, disease_code, parseFloat(lng), parseFloat(lat), village_id, severity, house_number, age, gender, nationality, occupation, onset_date || null, date_of_death || null, 
       reporterId] // 🌟 3. ส่งค่า reporterId เป็นพารามิเตอร์ที่ 14 ($14)
    );

    const nearbyResult = await pool.query('SELECT * FROM fn_get_vulnerable_nearby($1, $2, $3)', [parseFloat(lat), parseFloat(lng), 100]);

    let alertMsg = `ผู้ป่วยใหม่: ${name} (${diseaseResult.rows[0].name_th}) \nพิกัด: ${house_number} ต.${address?.tambon || 'พื้นที่'}`;
    if (nearbyResult.rowCount > 0) alertMsg += `\n⚠️ ระวัง! พบกลุ่มเปราะบาง ${nearbyResult.rowCount} รายในรัศมี 100 เมตร`;

    await pool.query(`INSERT INTO line_alerts (patient_id, channel_id, message, status, reporter_id) VALUES ($1, 'system', $2, 'sent', $3)`, [insertResult.rows[0].id, alertMsg, reporterId]);
    await sendLineAlert(alertMsg);

    res.status(201).json({ message: 'บันทึกผู้ป่วยสำเร็จ', patient: { id: insertResult.rows[0].id, name, disease_code }, alert_sent: true });
  } catch (error) {
    console.error('POST /api/patients', error);
    res.status(500).json({ error: 'ไม่สามารถบันทึกข้อมูลผู้ป่วยได้' });
  }
});

// 🌟 API สำหรับแท็บ 2: บันทึกข้อมูลคัดกรองสุขภาพจิตเชิงรุก (พร้อม SMI V-SCAN และ OAS)
app.post('/api/mental-screening', verifyToken, async (req, res) => {
  try {
    const { 
      name, lat, lng, address, age, gender, nationality, occupation, target_group, risk_level,
      smi_sleep, smi_pace, smi_talk, smi_irritable, smi_paranoia, smi_history, smi_history_detail,
      oas_self, oas_others, oas_property, oas_assessor // 🌟 1. รับค่า OAS เพิ่มเข้ามา
    } = req.body;
    
    const reporterId = req.userId;
    
    if (!name || lat == null || lng == null) return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });

    const fullAddress = `${address?.house_number || ''} ต.${address?.tambon || ''} อ.${address?.amphoe || ''}`.trim();

    // 2. บันทึกข้อมูลลงฐานข้อมูล (เพิ่มคอลัมน์ OAS เข้าไป)
    await pool.query(
      `INSERT INTO mental_screenings (
         name_th, age, gender, nationality, occupation, address_detail, location, target_group, risk_level, report_date, reporter_id,
         smi_sleep, smi_pace, smi_talk, smi_irritable, smi_paranoia, smi_history, smi_history_detail,
         oas_self, oas_others, oas_property, oas_assessor
       )
       VALUES ($1, $2, $3, $4, $5, $6, ST_SetSRID(ST_MakePoint($7, $8), 4326)::geography, $9, $10, CURRENT_DATE, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22)`,
      [
        name, age, gender, nationality, occupation, fullAddress, parseFloat(lng), parseFloat(lat), target_group, risk_level, reporterId,
        smi_sleep, smi_pace, smi_talk, smi_irritable, smi_paranoia, smi_history, smi_history_detail,
        oas_self, oas_others, oas_property, oas_assessor // 🌟 โยนค่า OAS ลง Database
      ]
    );

    // 3. จัดเตรียมข้อความแจ้งเตือน (ปรับปรุงให้รองรับ OAS)
    let alertMsg = `🧠 คัดกรองสุขภาพจิตใหม่: ${name}\nอายุ: ${age || '-'} ปี เพศ: ${gender}\nประเมินความเสี่ยง: ${risk_level}`;
    if (oas_self.includes('ฉุกเฉิน') || oas_others.includes('ฉุกเฉิน') || oas_property.includes('ฉุกเฉิน')) {
      alertMsg += `\n🚨 มีพฤติกรรมก้าวร้าวระดับ "ฉุกเฉิน" โปรดจัดการทันที!`;
    } else if (risk_level !== 'กลุ่มปกติ') {
      alertMsg += `\n🚨 โปรดติดตาม/นำเข้าสู่ระบบการรักษา`;
    }

    await pool.query(`INSERT INTO line_alerts (channel_id, message, status, reporter_id) VALUES ('system', $1, 'sent', $2)`, [alertMsg, reporterId]);
    await sendLineAlert(alertMsg);

    res.status(201).json({ message: 'บันทึกคัดกรองสุขภาพจิตสำเร็จ' });
  } catch (error) {
    console.error('POST /api/mental-screening error:', error);
    res.status(500).json({ error: 'ไม่สามารถบันทึกข้อมูลคัดกรองได้' });
  }
});

// 🌟 API สำหรับแท็บ 3: บันทึกข้อมูลติดตามผู้ป่วยจิตเวช
app.post('/api/psychiatric-patients', verifyToken, async (req, res) => {
  try {
    const { name, lat, lng, address, age, gender, nationality, occupation, psychiatric_group, follow_up_status } = req.body;
    const reporterId = req.userId;
    
    if (!name || lat == null || lng == null) return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });

    const fullAddress = `${address?.house_number || ''} ต.${address?.tambon || ''} อ.${address?.amphoe || ''}`.trim();

    // 1. บันทึกข้อมูลจิตเวช
    await pool.query(
      `INSERT INTO psychiatric_patients (name_th, age, gender, nationality, occupation, address_detail, location, psychiatric_group, follow_up_status, report_date, reporter_id)
       VALUES ($1, $2, $3, $4, $5, $6, ST_SetSRID(ST_MakePoint($7, $8), 4326)::geography, $9, $10, CURRENT_DATE, $11)`, // 🌟 2. เพิ่ม $11
      [name, age, gender, nationality, occupation, fullAddress, parseFloat(lng), parseFloat(lat), psychiatric_group, follow_up_status, 
       reporterId] // 🌟 3. ส่ง reporterId เข้าไป
    );

    // 2. จัดเตรียมข้อความแจ้งเตือน
    let alertMsg = `👥 ติดตามผู้ป่วยจิตเวช: ${name}\nกลุ่มอาการ: ${psychiatric_group}\nสถานะการติดตาม: ${follow_up_status}\nพิกัด: ${fullAddress}`;
    
    // 🌟 3. เพิ่มการแจ้งเตือนลงตาราง line_alerts เพื่อให้หน้า Alert ในแอปดึงไปโชว์
   await pool.query(`INSERT INTO line_alerts (channel_id, message, status, reporter_id) VALUES ('system', $1, 'sent', $2)`, [alertMsg, reporterId]);

    // 4. ส่งข้อความเข้า LINE (ของคุณทำไว้แล้ว)
    await sendLineAlert(alertMsg);

    res.status(201).json({ message: 'บันทึกติดตามผู้ป่วยจิตเวชสำเร็จ' });
  } catch (error) {
    console.error('POST /api/psychiatric-patients error:', error);
    res.status(500).json({ error: 'ไม่สามารถบันทึกข้อมูลจิตเวชได้' });
  }
});

// 🌟 API สำหรับลบข้อมูลผู้ป่วย (Delete Patient)
app.delete('/api/patients/:id', verifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    if (req.userRole !== 'hospital' && req.userRole !== 'staff' && req.userRole !== 'volunteer') {
      return res.status(403).json({ error: 'คุณไม่มีสิทธิ์ในการลบข้อมูลนี้' });
    }
    
    // เคลียร์ Log แจ้งเตือนก่อนลบป้องกัน Foreign Key ติด
    await pool.query('DELETE FROM line_alerts WHERE patient_id = $1', [id]);
    const result = await pool.query('DELETE FROM patients WHERE id = $1', [id]);
    
    if (result.rowCount === 0) return res.status(404).json({ error: 'ไม่พบข้อมูลผู้ป่วยที่ต้องการลบ' });
    res.json({ success: true, message: 'ลบข้อมูลผู้ป่วยเรียบร้อยแล้ว' });
  } catch (error) {
    console.error('DELETE /api/patients error:', error);
    res.status(500).json({ error: 'เกิดข้อผิดพลาดภายในเซิร์ฟเวอร์ ไม่สามารถลบข้อมูลได้' });
  }
});

// ─── DASHBOARD & MAPS ───

app.get('/api/stats/summary', async (req, res) => {
  try {
    const villageResult = await pool.query('SELECT id, moo, name_th, tambon, amphoe, province, population FROM villages ORDER BY id DESC LIMIT 1');
    const summaryResult = await pool.query(`
      SELECT COUNT(*) FILTER (WHERE report_date = CURRENT_DATE) AS new_today,
             COUNT(*) FILTER (WHERE report_date >= date_trunc('month', CURRENT_DATE)) AS total_this_month,
             (SELECT COUNT(*) FROM vulnerable_groups) AS vulnerable_total,
             (SELECT COUNT(*) FROM master_disease WHERE is_notifiable) AS disease_total,
             COUNT(*) AS total_patients
      FROM patients
    `);

    let areaName = 'พื้นที่รับผิดชอบ (ยังไม่ระบุข้อมูล)';
    if (villageResult.rowCount > 0) {
      const v = villageResult.rows[0];
      const popDisplay = v.population ? ` (ประชากร: ${new Intl.NumberFormat('th-TH').format(v.population)} คน)` : '';
      if (v.province.includes('กรุงเทพ') || v.province.toLowerCase() === 'bangkok') {
        let vName = (v.name_th && v.name_th !== v.tambon && v.name_th !== v.amphoe) ? `${v.name_th} ` : '';
        areaName = `${vName}แขวง${v.tambon} เขต${v.amphoe} ${v.province}${popDisplay}`;
      } else {
        areaName = `บ้าน${v.name_th} ม.${v.moo} ต.${v.tambon} อ.${v.amphoe} จ.${v.province}${popDisplay}`;
      }
    }

    res.json({
      area_name: areaName,
      new_today: parseInt(summaryResult.rows[0].new_today, 10) || 0,
      total_this_month: parseInt(summaryResult.rows[0].total_this_month, 10) || 0,
      vulnerable_total: parseInt(summaryResult.rows[0].vulnerable_total, 10) || 0,
      total_patients: parseInt(summaryResult.rows[0].total_patients, 10) || 0,
    });
  } catch (error) {
    res.status(500).json({ error: 'ไม่สามารถดึงสรุปสถิติได้' });
  }
});

// 🌟 แก้ไข: ดึงข้อมูลการแจ้งเตือนโดยจำกัดสิทธิ์ (RBAC)
app.get('/api/alerts', verifyToken, async (req, res) => { // ⚠️ ใส่ verifyToken
  try {
    const userId = req.userId;
    const userRole = req.userRole;
    let queryStr = "";
    let queryParams = [];

    if (userRole === 'admin' || userRole === 'executive' || userRole === 'hospital' || userRole === 'staff') {
      // ผู้บริหาร และ รพ.สต. เห็นแจ้งเตือนทั้งหมด
      queryStr = `SELECT id, message, sent_at, status FROM line_alerts ORDER BY sent_at DESC LIMIT 50`;
    } else {
      // อสม. เห็นเฉพาะแจ้งเตือนของเคสที่ตัวเองเป็นคนรายงาน
      queryStr = `SELECT id, message, sent_at, status FROM line_alerts WHERE reporter_id = $1 ORDER BY sent_at DESC LIMIT 50`;
      queryParams.push(userId);
    }

    const result = await pool.query(queryStr, queryParams);
    res.json(result.rows);
  } catch (error) {
    console.error('GET /api/alerts error:', error.message);
    res.status(500).json({ error: 'ไม่สามารถดึงข้อมูลการแจ้งเตือนได้' });
  }
});

// 🌟 API ดึงข้อมูลสถานที่ในชุมชน
app.get('/api/places', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT id, name_th as name, type, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng 
       FROM community_places`
    );
    res.json({ data: result.rows });
  } catch (error) {
    console.error('GET /api/places error:', error);
    res.status(500).json({ error: 'ไม่สามารถดึงข้อมูลสถานที่ได้' });
  }
});

// 🌟 API บันทึกสถานที่ในชุมชน
app.post('/api/places', async (req, res) => {
  try {
    const { name, type, lat, lng } = req.body;
    if (!name || !type || lat == null || lng == null) {
      return res.status(400).json({ error: 'ข้อมูลไม่ครบถ้วน' });
    }

    await pool.query(
      `INSERT INTO community_places (name_th, type, location)
       VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography)`,
      [name, type, parseFloat(lng), parseFloat(lat)]
    );

    res.status(201).json({ message: 'ปักหมุดสถานที่สำเร็จ' });
  } catch (error) {
    console.error('POST /api/places error:', error);
    res.status(500).json({ error: 'ไม่สามารถบันทึกสถานที่ได้' });
  }
});

// ─── EXPORT PATIENTS DATA TO EXCEL (WITH RBAC SECURITY) ───

app.get('/api/patients/export', async (req, res) => {
  try {
    // 🌟 ดักจับ Token จาก Query String เพื่อให้แอป Flutter เปิด Browser ดาวน์โหลดไฟล์ได้ง่ายๆ
    const token = req.query.token;
    if (!token) return res.status(401).json({ error: 'ไม่มีสิทธิ์เข้าถึงข้อมูล (Token Required)' });

    const decoded = jwt.verify(token, JWT_SECRET);
    const userId = decoded.userId;
    const userRole = decoded.role;

    let filterPatients = "";
    let filterMentalPsy = "";
    let queryParams = [];

    // 🛡️ ระบบสิทธิ์ (RBAC) กรองข้อมูลก่อนเจนไฟล์ Excel
    if (userRole === 'admin' || userRole === 'executive' || userRole === 'hospital' || userRole === 'staff') {
      filterPatients = "WHERE lat IS NOT NULL AND lng IS NOT NULL";
      filterMentalPsy = "WHERE location IS NOT NULL";
    } else {
      filterPatients = "WHERE lat IS NOT NULL AND lng IS NOT NULL AND reporter_id = $1";
      filterMentalPsy = "WHERE location IS NOT NULL AND reporter_id = $1";
      queryParams.push(userId);
    }

    // ดึงข้อมูลจากตารางทั้ง 3 ส่วน
    const patientsResult = await pool.query(`
      SELECT id, name_th, disease_code, disease_name, lat, lng, village_name, severity, report_date 
      FROM vw_patients_full ${filterPatients}
    `, queryParams);

    const mentalResult = await pool.query(`
      SELECT id, name_th, 'MH' AS disease_code, target_group AS disease_name, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng, address_detail AS village, risk_level AS severity, report_date 
      FROM mental_screenings ${filterMentalPsy}
    `, queryParams);

    const psychiatricResult = await pool.query(`
      SELECT id, name_th, 'PSY' AS disease_code, psychiatric_group AS disease_name, ST_Y(location::geometry) AS lat, ST_X(location::geometry) AS lng, address_detail AS village, follow_up_status AS severity, report_date 
      FROM psychiatric_patients ${filterMentalPsy}
    `, queryParams);

    // รวมข้อมูลลงในอาเรย์ก้อนเดียว
    let rows = [
      ...patientsResult.rows,
      ...mentalResult.rows,
      ...psychiatricResult.rows
    ];

    // จัดเรียงวันที่รายงานล่าสุดขึ้นก่อน
    rows.sort((a, b) => new Date(b.report_date) - new Date(a.report_date));

    // 📊 แปลงโครงสร้างให้กลายเป็นหัวข้อภาษาไทยใน Excel ให้อ่านง่าย
    const excelData = rows.map((r, index) => ({
      'ลำดับที่': index + 1,
      'ID ระบบ': r.id,
      'ชื่อ-นามสกุล': r.name_th || r.name,
      'รหัสประเภท': r.disease_code,
      'ประเภทโรค / แบบคัดกรอง / อาการ': r.disease_name,
      'ความรุนแรง / ผลประเมิน / สถานะ': r.severity,
      'พื้นที่รับผิดชอบ / ที่อยู่': r.village,
      'พิกัด (Latitude)': r.lat,
      'พิกัด (Longitude)': r.lng,
      'วันที่รายงาน': new Date(r.report_date).toISOString().split('T')[0]
    }));

    // 🏗️ กระบวนการสร้าง Workbook และ Sheet ของ Excel
    const wb = XLSX.utils.book_new();
    const ws = XLSX.utils.json_to_sheet(excelData);
    
    // ตั้งค่าความกว้างคอลัมน์แบบคร่าวๆ เพื่อให้เปิดมาแล้วตารางไม่บีบตัวหนังสือ
    ws['!cols'] = [
      { wch: 8 }, { wch: 10 }, { wch: 25 }, { wch: 12 }, { wch: 35 }, 
      { wch: 25 }, { wch: 40 }, { wch: 15 }, { wch: 15 }, { wch: 15 }
    ];

    XLSX.utils.book_append_sheet(wb, ws, "ข้อมูลรายงานสุขภาพ");

    // เขียนไฟล์ลง Buffer หน่วยความจำ
    const buffer = XLSX.write(wb, { type: 'buffer', bookType: 'xlsx' });

    // 🚀 พ่น Response Header บังคับให้ดาวน์โหลดเป็นไฟล์ .xlsx
    res.setHeader('Content-Disposition', 'attachment; filename=geo_health_report.xlsx');
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.send(buffer);

  } catch (error) {
    console.error('❌ Export Excel Error:', error.message);
    res.status(500).json({ error: 'ไม่สามารถส่งออกข้อมูลเป็น Excel ได้' });
  }
});

// ─── LINE WEBHOOK สำหรับดักจับ Group ID ───
app.post('/webhook', async (req, res) => {
  try {
    const events = req.body.events;
    
    // ตอบกลับ Status 200 ให้ LINE ทันที เพื่อไม่ให้ LINE มองว่าเกิด Error
    res.status(200).send('OK');

    if (events && events.length > 0) {
      for (const event of events) {
        if (event.type === 'message' && event.message.type === 'text') {
          const text = event.message.text.trim(); // ลบช่องว่างหน้าหลัง
          const source = event.source;

          // ถ้ามีคนพิมพ์คำว่า "getid" ไม่ว่าจะเป็นตัวพิมพ์เล็กหรือใหญ่
          if (text.toLowerCase() === 'getid') {
            let replyMessage = '';
            
            if (source.type === 'group') {
              console.log('📌 พบ Group ID:', source.groupId);
              replyMessage = `รหัสกลุ่มนี้คือ:\n${source.groupId}`;
            } else if (source.type === 'user') {
              console.log('📌 พบ User ID:', source.userId);
              replyMessage = `รหัส User ของคุณคือ:\n${source.userId}`;
            } else if (source.type === 'room') {
               console.log('📌 พบ Room ID:', source.roomId);
               replyMessage = `รหัส Room นี้คือ:\n${source.roomId}`;
            }

            const token = process.env.LINE_ACCESS_TOKEN;
            
            // 🌟 ตรวจสอบให้แน่ใจว่ามีทั้ง Token, ข้อความตอบกลับ และ replyToken
            if (token && replyMessage && event.replyToken) {
              try {
                await axios.post(
                  'https://api.line.me/v2/bot/message/reply',
                  {
                    replyToken: event.replyToken,
                    messages: [{ type: 'text', text: replyMessage }]
                  },
                  { headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` } }
                );
                console.log('✅ ตอบกลับ getid สำเร็จ!');
              } catch (err) {
                 console.error('❌ Reply Error:', err.response ? err.response.data : err.message);
              }
            } else {
               console.log('⚠️ ขาดข้อมูลในการตอบกลับ (Token, Message หรือ replyToken)');
            }
          }
        }
      }
    }
  } catch (error) {
    console.error('Webhook Error:', error);
    // กรณีที่ส่ง res.status(200) ไปแล้ว ไม่ควรส่ง res.status(500) ซ้ำ
  }
});

// 🌟 API สำหรับรีเซ็ตรหัสผ่านด้วยเลขบัตรประชาชน (ไม่ต้องใช้ OTP)
app.post('/api/reset-password-by-id', async (req, res) => {
  try {
    const { username, newPassword } = req.body;

    if (!username || !newPassword) {
      return res.status(400).json({ error: 'กรุณากรอกข้อมูลให้ครบถ้วน' });
    }

    // ตรวจสอบว่ามีผู้ใช้งานนี้ในระบบหรือไม่
    const userResult = await pool.query('SELECT * FROM users WHERE username = $1', [username]);
    if (userResult.rowCount === 0) {
      return res.status(404).json({ error: 'ไม่พบเลขบัตรประชาชนนี้ในระบบ' });
    }

    // เข้ารหัสผ่านใหม่และอัปเดตลงฐานข้อมูล
    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await pool.query(
      'UPDATE users SET password_hash = $1 WHERE username = $2',
      [hashedPassword, username]
    );

    res.status(200).json({ message: 'เปลี่ยนรหัสผ่านสำเร็จ' });
  } catch (error) {
    console.error('Reset Password By ID Error:', error);
    res.status(500).json({ error: 'เกิดข้อผิดพลาดในการเปลี่ยนรหัสผ่าน' });
  }
});

// Error Handler & Listener
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'เกิดข้อผิดพลาดภายในเซิร์ฟเวอร์' });
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`🚀 Server is running on port ${PORT}`);
});