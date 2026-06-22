-- ═══════════════════════════════════════════════════════════════════
-- Geo-Health Tracker — Database Schema (PostgreSQL + PostGIS)
-- รัน: psql -U postgres -d geohealth -f schema.sql
-- ═══════════════════════════════════════════════════════════════════

-- เปิดใช้งาน PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- สำหรับ UUID

-- ─── 1. ตาราง Master: กลุ่มโรค 506 ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS master_disease_group (
    code        VARCHAR(3) PRIMARY KEY,
    name_th     VARCHAR(100) NOT NULL,
    icd10_range VARCHAR(20),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 2. ตาราง Master: รายชื่อโรค ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS master_disease (
    code        VARCHAR(5)  PRIMARY KEY,
    group_code  VARCHAR(3)  REFERENCES master_disease_group(code),
    name_th     VARCHAR(200) NOT NULL,
    icd10       VARCHAR(10),
    is_notifiable BOOLEAN DEFAULT TRUE,  -- โรคที่ต้องรายงาน 506
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 3. ตาราง: หมู่บ้าน/ชุมชน ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS villages (
    id          SERIAL PRIMARY KEY,
    moo         INTEGER NOT NULL,          -- หมู่ที่
    name_th     VARCHAR(100) NOT NULL,
    tambon      VARCHAR(100),              -- ตำบล
    amphoe      VARCHAR(100),              -- อำเภอ
    province    VARCHAR(100),
    -- พิกัดศูนย์กลางหมู่บ้าน (SRID 4326 = WGS84)
    center      GEOGRAPHY(POINT, 4326),
    population  INTEGER DEFAULT 0,
    aor_id      INTEGER,                   -- รหัส อสม. รับผิดชอบ
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index เชิงพื้นที่สำหรับค้นหาหมู่บ้านใกล้เคียง
CREATE INDEX IF NOT EXISTS idx_villages_center ON villages USING GIST(center);

-- ─── 3.5. ตาราง: ผู้ใช้ระบบ (Authentication) ──────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    username        VARCHAR(100) NOT NULL UNIQUE,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,           -- bcrypt hashed
    name_th         VARCHAR(200),
    role            VARCHAR(20) DEFAULT 'volunteer' CHECK(role IN ('admin', 'volunteer', 'supervisor')),
    is_active       BOOLEAN DEFAULT TRUE,
    last_login_at   TIMESTAMPTZ,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

-- ─── 4. ตาราง: อาสาสมัครสาธารณสุข (อสม.) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS health_volunteers (
    id          SERIAL PRIMARY KEY,
    name_th     VARCHAR(200) NOT NULL,
    phone       VARCHAR(15),
    line_uid    VARCHAR(100),              -- LINE User ID สำหรับ Push Notification
    village_id  INTEGER REFERENCES villages(id),
    is_active   BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── 5. ตาราง: ผู้ป่วย ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS patients (
    id              SERIAL PRIMARY KEY,
    hn              VARCHAR(20),           -- HN จากระบบ HIS ของ รพ.
    name_th         VARCHAR(200) NOT NULL,
    age             INTEGER,
    gender          CHAR(1) CHECK(gender IN ('M','F')),
    disease_code    VARCHAR(5) REFERENCES master_disease(code),
    
    -- พิกัด GPS ที่ อสม. ปักหมุด (SRID 4326)
    -- PostGIS จัดเก็บเป็น GEOGRAPHY เพื่อคำนวณระยะทางแบบ spherical ได้ทันที
    location        GEOGRAPHY(POINT, 4326) NOT NULL,
    
    village_id      INTEGER REFERENCES villages(id),
    severity        VARCHAR(10) CHECK(severity IN ('mild','moderate','severe')) DEFAULT 'mild',
    report_date     DATE DEFAULT CURRENT_DATE,
    reporter_id     INTEGER REFERENCES health_volunteers(id),
    
    -- PDPA: บันทึกว่าผู้ป่วยยินยอมให้เก็บข้อมูลพิกัด
    pdpa_consent    BOOLEAN DEFAULT FALSE,
    pdpa_consent_at TIMESTAMPTZ,
    
    -- Audit
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Index เชิงพื้นที่ — ทำให้ ST_DWithin() ค้นหาในรัศมีได้เร็วมาก
CREATE INDEX IF NOT EXISTS idx_patients_location   ON patients USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_patients_disease     ON patients(disease_code);
CREATE INDEX IF NOT EXISTS idx_patients_report_date ON patients(report_date);
CREATE INDEX IF NOT EXISTS idx_patients_village     ON patients(village_id);

-- ─── 6. ตาราง: กลุ่มเปราะบาง ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS vulnerable_groups (
    id              SERIAL PRIMARY KEY,
    name_th         VARCHAR(200) NOT NULL,
    type            VARCHAR(50) NOT NULL, -- 'ผู้สูงอายุ','ทารก','หญิงตั้งครรภ์','ผู้พิการ','โรคเรื้อรัง'
    condition_notes TEXT,                 -- รายละเอียดโรคประจำตัว
    
    -- พิกัดบ้าน
    location        GEOGRAPHY(POINT, 4326) NOT NULL,
    village_id      INTEGER REFERENCES villages(id),
    
    phone           VARCHAR(15),
    guardian_name   VARCHAR(200),         -- ชื่อผู้ดูแล
    guardian_phone  VARCHAR(15),
    
    pdpa_consent    BOOLEAN DEFAULT FALSE,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vulnerable_location ON vulnerable_groups USING GIST(location);
CREATE INDEX IF NOT EXISTS idx_vulnerable_village  ON vulnerable_groups(village_id);

-- ─── 7. ตาราง: บันทึกการแจ้งเตือน LINE ──────────────────────────────────
CREATE TABLE IF NOT EXISTS line_alerts (
    id          SERIAL PRIMARY KEY,
    patient_id  INTEGER REFERENCES patients(id),
    channel_id  VARCHAR(100) NOT NULL,   -- LINE Group ID หรือ User ID
    message     TEXT NOT NULL,
    sent_at     TIMESTAMPTZ DEFAULT NOW(),
    status      VARCHAR(20) DEFAULT 'sent' CHECK(status IN ('sent','failed','pending'))
);

-- ─── 8. View: แสดงผู้ป่วยพร้อมชื่อโรคและหมู่บ้าน (ใช้ใน Dashboard) ─────
CREATE OR REPLACE VIEW vw_patients_full AS
SELECT
    p.id,
    p.name_th,
    p.age,
    p.gender,
    p.disease_code,
    d.name_th        AS disease_name,
    p.severity,
    p.report_date,
    v.name_th        AS village_name,
    v.moo,
    v.amphoe,
    -- แปลง GEOGRAPHY เป็น lat/lng สำหรับส่งให้ Frontend
    ST_Y(p.location::geometry) AS lat,
    ST_X(p.location::geometry) AS lng
FROM patients p
LEFT JOIN master_disease d ON p.disease_code = d.code
LEFT JOIN villages v       ON p.village_id   = v.id;

-- ─── 9. Function: ค้นหากลุ่มเปราะบางในรัศมี (หัวใจของระบบ) ──────────────
CREATE OR REPLACE FUNCTION fn_get_vulnerable_nearby(
    p_lat    DOUBLE PRECISION,
    p_lng    DOUBLE PRECISION,
    p_radius INTEGER DEFAULT 100   -- หน่วย: เมตร
)
RETURNS TABLE (
    id              INTEGER,
    name_th         VARCHAR,
    type            VARCHAR,
    condition_notes TEXT,
    distance_meters DOUBLE PRECISION
) AS $$
BEGIN
    -- ST_DWithin ใช้ GEOGRAPHY จึงคำนวณระยะทางแบบ spherical (หน่วยเมตร)
    -- Index GIST บน location ทำให้ query นี้เร็วมากแม้ข้อมูลเป็นล้านแถว
    RETURN QUERY
    SELECT
        vg.id,
        vg.name_th,
        vg.type,
        vg.condition_notes,
        ROUND(
            ST_Distance(
                vg.location,
                ST_MakePoint(p_lng, p_lat)::geography
            )::NUMERIC, 1
        )::DOUBLE PRECISION AS distance_meters
    FROM vulnerable_groups vg
    WHERE ST_DWithin(
        vg.location,
        ST_MakePoint(p_lng, p_lat)::geography,
        p_radius
    )
    ORDER BY distance_meters;
END;
$$ LANGUAGE plpgsql;

-- ─── Sample Data ──────────────────────────────────────────────────────────
INSERT INTO master_disease_group (code, name_th) VALUES
    ('01', 'โรคระบบทางเดินอาหาร'),
    ('26', 'โรคไข้เลือดออก'),
    ('32', 'โรคพิษสุนัขบ้า'),
    ('65', 'โรคระบบทางเดินหายใจ'),
    ('71', 'โรคมือเท้าปาก')
ON CONFLICT (code) DO NOTHING;

INSERT INTO master_disease (code, group_code, name_th, icd10) VALUES
    ('01', '01', 'อหิวาตกโรค', 'A00'),
    ('02', '01', 'อาหารเป็นพิษ', 'A05'),
    ('26', '26', 'ไข้เลือดออก', 'A97'),
    ('32', '32', 'โรคพิษสุนัขบ้า', 'A82'),
    ('65', '65', 'ไข้หวัดใหญ่', 'J10'),
    ('71', '71', 'มือเท้าปาก', 'B08')
ON CONFLICT (code) DO NOTHING;

-- ─── ตัวอย่างการ Query (ทดสอบ) ──────────────────────────────────────────────
-- ค้นหากลุ่มเปราะบางในรัศมี 100 เมตรรอบผู้ป่วยรายใหม่:
--   SELECT * FROM fn_get_vulnerable_nearby(14.9798, 102.0978, 100);
--
-- ดูผู้ป่วยทั้งหมดพร้อมพิกัด:
--   SELECT * FROM vw_patients_full WHERE report_date = CURRENT_DATE;
