# OCPP 1.6J Central System

เว็บแอปสำหรับเป็น Central System (Server) รองรับโปรโตคอล **OCPP 1.6J** (JSON over WebSocket)
ใช้เชื่อมต่อและควบคุมเครื่องชาร์จรถยนต์ไฟฟ้า (EV Charger) พร้อม Dashboard สำหรับดูสถานะเครื่อง,
ประวัติการชาร์จ (Transaction) และสั่งงานระยะไกล (Remote Start/Stop, Unlock, Reset)

## โครงสร้างโปรเจกต์

```
.
├── app/
│   ├── main.py           # FastAPI app: WebSocket OCPP + REST API + serve dashboard
│   ├── ocpp_handler.py   # Logic รับ/ส่ง OCPP message (BootNotification, StartTransaction, ฯลฯ)
│   ├── database.py       # SQLAlchemy models (SQLite)
│   └── static/           # หน้าเว็บ Dashboard (HTML/CSS/JS ล้วน ไม่ต้อง build)
├── Dockerfile
├── docker-compose.yml
├── requirements.txt
└── README.md
```

## รันทดสอบในเครื่อง (Local)

```bash
python -m venv venv
source venv/bin/activate        # Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 9000 --reload
```

เปิดเบราว์เซอร์ไปที่ `http://localhost:9000` จะเห็น Dashboard

หรือรันผ่าน Docker Compose:

```bash
docker compose up --build
```

## เชื่อมต่อเครื่องชาร์จจริง

ตั้งค่า **Central System URL** ในตัวเครื่องชาร์จ (ผ่านหน้าจอเครื่อง/เว็บ config ของผู้ผลิต) เป็น:

```
ws://<IP หรือ Domain ของ server>:9000/ocpp/<ChargePointID>
```

หรือถ้า deploy ด้วย HTTPS/Coolify (มี TLS ให้อัตโนมัติ):

```
wss://<domain ที่ Coolify ตั้งให้>/ocpp/<ChargePointID>
```

`ChargePointID` ตั้งเป็นชื่ออะไรก็ได้ แต่ต้องจำไว้ใช้อ้างอิงในระบบ (เช่น `CP001`)

## API หลักที่ Dashboard เรียกใช้

| Endpoint | Method | คำอธิบาย |
|---|---|---|
| `/api/charge-points` | GET | รายการเครื่องชาร์จทั้งหมด + สถานะ |
| `/api/transactions` | GET | ประวัติการชาร์จ |
| `/api/events` | GET | Log ของทุก OCPP message ที่เข้ามา |
| `/api/charge-points/{id}/remote-start` | POST | สั่งเริ่มชาร์จระยะไกล |
| `/api/charge-points/{id}/remote-stop` | POST | สั่งหยุดชาร์จระยะไกล |
| `/api/charge-points/{id}/unlock` | POST | ปลดล็อคหัวชาร์จ |
| `/api/charge-points/{id}/reset` | POST | สั่ง Reset เครื่อง (Soft/Hard) |

## การสร้าง GitHub Repo แล้ว Push โค้ดขึ้นไป

โปรเจกต์นี้ init เป็น git repo ในเครื่องเรียบร้อยแล้ว (ดูขั้นตอนที่แนบมาในแชท)
ให้ทำตามนี้เพื่อขึ้น GitHub:

1. ไปที่ https://github.com/new สร้าง repository ใหม่ (เช่นชื่อ `ocpp-central-system`)
   **ไม่ต้อง** ติ๊กเลือก "Add a README file" (เพราะมีอยู่แล้ว)
2. ที่เครื่องคุณ (โฟลเดอร์โปรเจกต์นี้) รันคำสั่ง:

```bash
git remote add origin https://github.com/<username>/ocpp-central-system.git
git branch -M main
git push -u origin main
```

## Deploy บน Coolify

1. ใน Coolify: **New Resource → Application → Public/Private Repository (GitHub)**
2. เลือก repo นี้ที่เพิ่ง push ขึ้นไป, branch `main`
3. Build Pack เลือก **Dockerfile** (Coolify จะเจอ `Dockerfile` ในโปรเจกต์อัตโนมัติ)
4. **Port**: ตั้งเป็น `9000` (ให้ตรงกับที่ Dockerfile เปิดไว้)
5. **Persistent Storage**: เพิ่ม volume mount path `/app/data` เพื่อไม่ให้ฐานข้อมูล SQLite หายเวลา redeploy
   - ระบบ backup อัตโนมัติ (ทุก 24 ชม. โดย default, ตั้งค่าได้ผ่าน `BACKUP_INTERVAL_HOURS`/`BACKUP_RETENTION_COUNT`)
     จะเก็บไฟล์ไว้ที่ `/app/data/backups` บน volume เดียวกัน — Export/Restore ด้วยตัวเองได้จากหน้า Admin → Backup
6. Deploy — Coolify จะออก domain + TLS (`https://`) ให้อัตโนมัติ
   - Dashboard เปิดที่ `https://<domain>`
   - เครื่องชาร์จเชื่อมต่อ WebSocket ที่ `wss://<domain>/ocpp/<ChargePointID>`

> **หมายเหตุ**: ถ้าเครื่องชาร์จของคุณรองรับเฉพาะ `ws://` (ไม่มี TLS) และอยู่ใน local network เดียวกับ
> server ให้ deploy แบบเปิด port ตรงแทนการผ่าน Coolify's reverse proxy หรือใช้ domain ภายในองค์กรแทน

## ข้อควรทำต่อ (Production checklist)

- [ ] เพิ่มระบบ Authentication สำหรับ Dashboard (ตอนนี้ยังเปิดเข้าได้ทุกคน)
- [ ] เพิ่ม Basic Auth / Token สำหรับ endpoint `/ocpp/*` (OCPP 1.6J รองรับ HTTP Basic Auth ผ่าน header)
- [ ] เปลี่ยนจาก SQLite เป็น PostgreSQL ถ้ามีเครื่องชาร์จจำนวนมาก / concurrent สูง
- [ ] เพิ่มระบบ user/บัตร RFID จริงใน `on_authorize` (ตอนนี้ accept ทุกใบ)
- [ ] เพิ่ม HTTPS/WSS บังคับ (Coolify จัดการให้อัตโนมัติผ่าน reverse proxy อยู่แล้ว)
