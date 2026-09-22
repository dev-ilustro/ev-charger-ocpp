# Task List: เปิด ws:// (non-TLS) endpoint เพื่อทดสอบเครื่องชาร์จที่ TLS handshake ไม่ผ่าน

## บริบทปัญหา
- Server (`wss://ev.ilustro.co/ocpp/...`) ทดสอบด้วย curl แล้ว handshake ผ่านสมบูรณ์ (101 Switching Protocols + subprotocol `ocpp1.6` ถูกต้อง)
- เครื่องชาร์จจริง (YCLEVSE, firmware TLS เก่า) เจอ "Recv error" ตอนเชื่อมต่อ — สงสัยว่า TLS library ของเครื่องเก่าเกินไป ไม่รองรับ cipher/cert ที่ server สมัยใหม่ใช้
- เปิด endpoint แบบไม่มี TLS (`ws://`) แยกไว้ทดสอบ เพื่อพิสูจน์ว่าใช่ปัญหา TLS จริงไหม

---

## Task 1 — เช็คโค้ด app/main.py และ app/ocpp_handler.py ✅ DONE (2026-07-27)

**ผลตรวจสอบ:**
- ✅ ไม่มี `HTTPSRedirectMiddleware` หรือโค้ดใดๆ ที่ force redirect http → https
- ✅ ไม่มีการเช็ค `request.url.scheme` หรือ header แบบ hardcode ใน [app/main.py](app/main.py) หรือ [app/ocpp_handler.py](app/ocpp_handler.py)
- ✅ Route `/ocpp/{charge_point_id}` ([app/main.py:105](app/main.py#L105)) accept WebSocket ตรงๆ ผ่าน `FastAPIWebSocketAdapter` — ไม่สน scheme เพราะ TLS termination ทำที่ layer หน้า (Coolify/Traefik) ไม่ใช่ที่ uvicorn
- ⚠️ **พบเพิ่ม (สำคัญสำหรับ security task ด้านล่าง):** endpoint `/ocpp/{charge_point_id}` ปัจจุบัน **ไม่มี authentication ใดๆ เลย** — ใครก็ต่อเข้ามาอ้างเป็น charge point ไหนก็ได้ แล้วสั่ง OCPP message ได้ทันที

**สรุป:** ฝั่งโค้ดไม่ต้องแก้อะไรสำหรับให้ ws:// ทำงาน — ปัญหาทั้งหมดอยู่ที่ layer ของ Coolify/reverse proxy (Task 2)

---

## Task 2 — ตั้งค่าที่ Coolify ให้เปิด HTTP entrypoint แยก (ไม่ auto-redirect ไป HTTPS)

**ต้องทำเอง (นอกเหนือ code, เข้าถึง Coolify dashboard):**

- [ ] เข้า Coolify → application `ev-charger-ocpp` → Configuration → General/Network
- [ ] หา option "Force HTTPS" / "Redirect to HTTPS" → ปิดชั่วคราว (หรือถ้ามี option เพิ่ม domain/port แยกสำหรับ HTTP โดยเฉพาะ ใช้ทางนั้นแทน จะไม่กระทบ dashboard หลัก)
- [ ] ทดสอบว่า `http://ev.ilustro.co/ocpp/test123` เข้าถึงได้โดยไม่ redirect ไป https อัตโนมัติ

---

## Task 3 — ทดสอบด้วย curl ว่า ws:// (plain) ใช้งานได้จริง

รันจากคอมพิวเตอร์ (ไม่ใช่จากเครื่องชาร์จ) หลังทำ Task 2 เสร็จ:

```powershell
curl.exe -v -N -H "Connection: Upgrade" -H "Upgrade: websocket" -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==" -H "Sec-WebSocket-Protocol: ocpp1.6" http://ev.ilustro.co/ocpp/test123
```

- [ ] ต้องได้ `HTTP/1.1 101 Switching Protocols` กลับมาเหมือนตอนทดสอบ wss

*(บอกได้เลยเมื่อ Task 2 เสร็จแล้ว — รันคำสั่งนี้ให้ทันที)*

---

## Task 4 — ตั้งค่าที่เครื่องชาร์จ ทดสอบด้วย ws://

ที่แอพมือถือ → เมนู OCPP1.6 → เปลี่ยน:
- Protocol head: `wss` → `ws`
- Server port: `443` → `80`
- Connection path: เหมือนเดิม (`ocpp`)

- [ ] กด Confirm แล้วเช็คว่ายังขึ้น "Recv error" ไหม

---

## Task 5 — เช็คผลลัพธ์

- [ ] เปิด `https://ev.ilustro.co/api/events` ดูว่ามี event `BootNotification` เข้ามาไหม
- [ ] **ถ้าเข้ามา** = ยืนยันว่าเป็นปัญหา TLS ของเครื่องชาร์จแน่นอน → ตัดสินใจว่าจะใช้ ws ถาวร (ไม่เข้ารหัส) หรือหาทางแก้ TLS compatibility ต่อ
- [ ] **ถ้ายังไม่เข้ามา** = ปัญหาไม่ใช่ TLS อย่างเดียว → กลับไปดู log เครื่องชาร์จเพิ่มเติม

---

## Task 6 — Security: เพิ่ม auth ที่ /ocpp/* (ทำก่อนใช้ ws:// ถาวร)

**เหตุผล:** จาก Task 1 พบว่า endpoint `/ocpp/{charge_point_id}` ไม่มี auth เลยตอนนี้ — ถ้าเปลี่ยนไปใช้ ws:// (ไม่เข้ารหัส) แบบถาวรโดยไม่มี auth ใครก็ปลอมตัวเป็นเครื่องชาร์จ หรือดักฟัง/ปลอม remote-start/stop ได้

- [ ] เพิ่ม token/API-key check ก่อน `websocket.accept()` ใน [app/main.py:110](app/main.py#L110) เช่น query param `?token=...` หรือ HTTP Basic Auth header ตรวจก่อนรับ connection (ตรง OCPP 1.6J spec รองรับ HTTP Basic Auth บน WebSocket handshake อยู่แล้ว)
- [ ] เก็บ token/credential ต่อเครื่อง (per charge point) ไว้ใน DB (ตาราง `ChargePointDB` มีอยู่แล้ว เพิ่ม column ได้)
- [ ] ถ้าทำได้ในระดับ Coolify: เปิด Force HTTPS กลับสำหรับ `/`, `/api/*` เหมือนเดิม ยกเว้นเฉพาะ `/ocpp/*` — ถ้า Coolify ทำละเอียดขนาดนั้นไม่ได้ ให้พิจารณาแยก subdomain เช่น `ws.ev.ilustro.co` สำหรับ ws เฉยๆ

*(รอผลจาก Task 5 ก่อนว่าจะใช้ ws ถาวรจริงไหม — ยังไม่ implement จนกว่าจะ confirm)*

---

## สถานะรวม

| Task | ผู้ทำ | สถานะ |
|---|---|---|
| 1. ตรวจโค้ด | Claude Code | ✅ เสร็จแล้ว — ไม่มีปัญหา |
| 2. Coolify config | ผู้ใช้ (ต้องเข้า dashboard) | ⬜ รอทำ |
| 3. curl test | Claude Code (รันให้ได้ทันทีหลัง Task 2) | ⬜ รอ Task 2 |
| 4. ตั้งค่าเครื่องชาร์จ | ผู้ใช้ (หน้างานจริง) | ⬜ รอ Task 3 |
| 5. เช็คผลลัพธ์ | ร่วมกัน | ⬜ รอ Task 4 |
| 6. เพิ่ม auth | Claude Code (เมื่อ confirm ใช้ ws ถาวร) | ⬜ รอผล Task 5 |
