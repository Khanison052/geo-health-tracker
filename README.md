# 🏥 Geo-Health Tracker — Enterprise Edition

ระบบติดตามและเฝ้าระวังสุขภาพชุมชนเชิงพื้นที่แบบเรียลไทม์ สำหรับ อสม. รพ.สต. และผู้บริหาร สอดคล้องตาม พ.ร.บ. คุ้มครองข้อมูลส่วนบุคคล (PDPA 2562) พร้อมระบบวิเคราะห์การระบาด (Automated Ring Strategy)

## 📁 โครงสร้างโปรเจกต์ (Monorepo)

```text
geo-health-tracker/
├── .github/
│   └── workflows/
│       └── node-cd.yml      ← ระบบ CI/CD (GitHub Actions) สำหรับ Auto-Deploy
├── backend/
│   ├── server.js            ← Node.js + Express API (Production on Render.com)
│   ├── schema.sql           ← PostgreSQL + PostGIS database schema
│   └── package.json
└── mobile/
    ├── lib/
    │   ├── src/             
    │   └── main.dart        ← Flutter app (iOS + Android + Web)
    └── pubspec.yaml
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

## 🚀 การ Deploy และรัน Backend API (Production)

ระบบปัจจุบันถูกออกแบบสถาปัตยกรรมมารองรับการทำงานบนคลาวด์ (เช่น Render.com) โดยมีระบบ CI/CD Pipeline ควบคุมการ Deploy อัตโนมัติ

**แบบที่ 1: การอัปเดตระบบขึ้น Cloud (Auto-Deploy ผ่าน CI/CD)**
เมื่อมีการแก้ไขโค้ดฝั่ง `backend/` ให้ทำตามขั้นตอนดังนี้:
```bash
# 1. บันทึกการเปลี่ยนแปลง
git add .
git commit -m "Update backend features"

# 2. อัปโหลดขึ้น GitHub (สาขา main)
git push origin main
```
Note: ระบบ GitHub Actions จะทำการตรวจสอบโค้ด และส่ง Webhook ไปกระตุ้นให้เซิร์ฟเวอร์คลาวด์ดึงโค้ดชุดใหม่ไปติดตั้งและรัน (npm install -> node server.js) โดยอัตโนมัติแบบ Zero Downtime


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

async function sendLineAlert(message) {
  const token = process.env.LINE_NOTIFY_TOKEN;
  if (!token) return;

  try {
    const params = new URLSearchParams();
    params.append('message', `\n${message}`); 

    await axios.post('[https://notify-api.line.me/api/notify](https://notify-api.line.me/api/notify)', params, { 
      headers: { 
        'Content-Type': 'application/x-www-form-urlencoded', 
        'Authorization': `Bearer ${token}` 
      } 
    });
  } catch (error) {
    console.error('❌ ส่งแจ้งเตือน LINE พลาด:', error.message);
  }
}
```

---

## 📝 Roadmap สู่ Production

- [x] เชื่อม PostgreSQL + PostGIS บน Cloud จริง
- [x] ระบบ JWT Authentication & RBAC (Admin, Hospital, Volunteer)
- [x] แจ้งเตือน LINE (เปลี่ยนเป็น LINE Notify เพื่อแก้ปัญหาโควต้าเต็ม)
- [x] อัปเกรดแผนที่เป็น OpenStreetMap (flutter_map) ทะลุข้อจำกัด Web Proxy
- [x] เพิ่มระบบคัดกรองจิตเวช (SMI V-SCAN, OAS) แบบครบวงจร
- [x] วางระบบ CI/CD Pipeline ด้วย GitHub Actions Deploy ขึ้น Render.com
- [x] ระบบ Export ข้อมูลผู้ป่วยและกลุ่มเปราะบางออกเป็นไฟล์ Excel
- [ ] เพิ่ม Offline Mode (SQLite local + sync เมื่อมีสัญญาณอินเทอร์เน็ต)
- [ ] เชื่อมต่อ API กับระบบฐานข้อมูลสาธารณสุขระดับประเทศ (HDC)
