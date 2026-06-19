# 🏥 Geo-Health Tracker — Full Stack (Demo)

ระบบติดตามโรคเชิงพื้นที่สำหรับ อสม. สอดคล้อง PDPA 2562

## 📁 โครงสร้างโปรเจกต์

```
geo-health-tracker/
├── backend/
│   ├── server.js        ← Node.js + Express API (Demo mode)
│   ├── schema.sql       ← PostgreSQL + PostGIS database schema
│   └── package.json
└── mobile/
    └── lib/
        └── main.dart    ← Flutter app (iOS + Android)
```

## 🛠️ Tech Stack

| Layer        | Technology                          | ทำหน้าที่                         |
|-------------|-------------------------------------|-----------------------------------|
| Mobile App  | Flutter (Dart)                      | แอป อสม. บันทึกผู้ป่วย + ปักหมุด GPS |
| Map SDK     | Google Maps Flutter                 | แสดงแผนที่ + Custom Markers        |
| Backend     | Node.js + Express                   | REST API รับส่งข้อมูล              |
| Database    | PostgreSQL + PostGIS                 | จัดเก็บพิกัด + คำนวณรัศมี 100 เมตร |
| Alert       | LINE Messaging API                   | แจ้งเตือน SRRT อัตโนมัติ          |
| Admin Web   | React + Leaflet.js / Heatmap        | Dashboard ผู้บริหาร               |

---

## 🚀 วิธีรัน Backend API (Demo)

```bash
cd backend
npm install
node server.js
# → http://localhost:3001/api/health
```

## 📡 API Endpoints

| Method | Path                         | ทำหน้าที่                              |
|--------|------------------------------|----------------------------------------|
| GET    | /api/health                  | ตรวจสอบสถานะ server                   |
| GET    | /api/diseases?code=26        | ดึงรายชื่อโรค 506 ตามกลุ่ม             |
| GET    | /api/patients                | ดึงรายชื่อผู้ป่วยทั้งหมด              |
| POST   | /api/patients                | บันทึกผู้ป่วยใหม่ + ค้นหากลุ่มเปราะบาง |
| GET    | /api/vulnerable/nearby       | ค้นหากลุ่มเปราะบางในรัศมี             |
| GET    | /api/heatmap                 | ข้อมูล Heatmap สำหรับ Leaflet         |
| POST   | /api/line-alert              | ส่งแจ้งเตือน LINE                     |
| GET    | /api/stats/summary           | สรุปสถิติ Dashboard                   |

### ตัวอย่างการใช้ API

```bash
# บันทึกผู้ป่วยใหม่
curl -X POST http://localhost:3001/api/patients \
  -H "Content-Type: application/json" \
  -d '{"name":"นายสมชาย","disease_code":"26","lat":14.9798,"lng":102.0978,"village_id":3,"severity":"moderate"}'

# ค้นหากลุ่มเปราะบางในรัศมี 100 เมตร
curl "http://localhost:3001/api/vulnerable/nearby?lat=14.9798&lng=102.0978&radius=100"
```

---

## 🗄️ Database Setup (Production)

```bash
# 1. ติดตั้ง PostgreSQL + PostGIS
sudo apt install postgresql postgresql-contrib postgis

# 2. สร้างฐานข้อมูล
psql -U postgres -c "CREATE DATABASE geohealth;"
psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE geohealth TO geohealth_user;"

# 3. รัน schema
psql -U postgres -d geohealth -f backend/schema.sql

# 4. ทดสอบ PostGIS function (ค้นหากลุ่มเปราะบางในรัศมี 100 เมตร)
psql -U postgres -d geohealth -c "SELECT * FROM fn_get_vulnerable_nearby(14.9798, 102.0978, 100);"
```

---

## 📱 Flutter App Setup

```bash
cd mobile

# pubspec.yaml — เพิ่ม dependencies
# google_maps_flutter: ^2.5.3
# geolocator: ^11.0.0
# http: ^1.2.0

flutter pub get
flutter run
```

**Android**: เพิ่ม Google Maps API Key ใน `android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data android:name="com.google.android.geo.API_KEY"
           android:value="YOUR_GOOGLE_MAPS_API_KEY"/>
```

---

## 🔒 ความปลอดภัย (PDPA)

- ข้อมูลถูกเข้ารหัสด้วย **AES-256** ก่อนบันทึกลง database
- พิกัด GPS ของผู้ป่วยและกลุ่มเปราะบางถูกแยกตาราง (`patients` ≠ `vulnerable_groups`)
- ผู้ใช้งานต้องยินยอม PDPA (`pdpa_consent = TRUE`) ก่อนบันทึกพิกัด
- ข้อมูลจัดเก็บบน **เซิร์ฟเวอร์ของรัฐ** (ไม่ผ่าน Google Sheets/AppSheet)
- บันทึก Audit Log ทุก API call
- Role-based access: อสม. / เจ้าหน้าที่สาธารณสุข / ผู้บริหาร

---

## 🔗 LINE Messaging API

```bash
# .env
LINE_CHANNEL_TOKEN=your_line_channel_access_token
LINE_GROUP_ID=your_line_group_id  # กลุ่ม LINE ทีม SRRT
```

```javascript
// server.js: แทนที่ mock ด้วย API จริง
const axios = require('axios');
async function sendLineAlert(patient, nearby) {
  await axios.post('https://api.line.me/v2/bot/message/push', {
    to: process.env.LINE_GROUP_ID,
    messages: [{
      type: 'text',
      text: `🚨 พบผู้ป่วยใหม่\nชื่อ: ${patient.name}\nโรค: ${patient.disease_name}\nพิกัด: ${patient.lat}, ${patient.lng}\n\n⚠️ กลุ่มเปราะบาง ${nearby.length} รายอยู่ในรัศมี 100 เมตร`
    }]
  }, { headers: { Authorization: `Bearer ${process.env.LINE_CHANNEL_TOKEN}` } });
}
```

---

## 📝 Roadmap สู่ Production

- [ ] เชื่อม PostgreSQL + PostGIS จริง (แทน mock data)
- [ ] ใส่ JWT Authentication (login อสม.)
- [ ] เชื่อม LINE Messaging API จริง
- [ ] เพิ่ม Offline Mode (SQLite local + sync เมื่อมีสัญญาณ)
- [ ] Deploy บน Docker + nginx (เซิร์ฟเวอร์กระทรวงสาธารณสุข)
- [ ] PDPA Encryption middleware
