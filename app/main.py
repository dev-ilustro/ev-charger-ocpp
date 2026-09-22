"""
Entry point ของแอป: รวม
  - OCPP 1.6J WebSocket endpoint ที่เครื่องชาร์จเชื่อมต่อเข้ามา  ->  /ocpp/{charge_point_id}
  - REST API สำหรับ dashboard                                     ->  /api/*
  - เสิร์ฟหน้าเว็บ dashboard (static)                               ->  /
รันด้วย: uvicorn app.main:app --host 0.0.0.0 --port 9000
"""

import asyncio
import logging
import os
import re
import tempfile
from datetime import datetime, timedelta
from typing import Optional
from uuid import uuid4

from fastapi import (
    Cookie,
    Depends,
    FastAPI,
    File,
    HTTPException,
    Request,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from ocpp.exceptions import OCPPError
from pydantic import BaseModel

from app.auth import (
    ACCESS_TOKEN_COOKIE_NAME,
    ACCESS_TOKEN_EXPIRE_DAYS,
    create_access_token,
    decode_access_token,
    hash_password,
    is_legacy_hash,
    verify_password,
)
from app.backup import BACKUP_DIR, create_backup, list_backups, restore_from_file, scheduled_backup_loop
from app.database import (
    CardTapDB,
    ChangelogDB,
    ChargePointDB,
    EventLogDB,
    MeterValueDB,
    RFIDCardDB,
    SessionLocal,
    TransactionDB,
    UserDB,
    WalletLedgerDB,
    WalletPaymentDB,
    get_settings,
    init_db,
    resolve_card_authorization,
    seed_defaults,
)
from app.ocpp_handler import CONNECTED_CHARGE_POINTS, ChargePoint, cleanup_charge_point, log_event

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("ocpp-server")

app = FastAPI(title="OCPP 1.6J Central System")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def add_static_no_cache_headers(request: Request, call_next):
    """หน้าเว็บ static (HTML/CSS/JS) ให้ browser revalidate ทุกครั้งผ่าน ETag แทนที่จะ cache
    เงียบๆ ตาม heuristic ของ browser เอง — กัน deploy เวอร์ชันใหม่ไปแล้วแต่ผู้ใช้ยังเห็นหน้าเก่าค้างอยู่
    โดยไม่รู้ตัว (ไม่กระทบ /api เพราะ response พวกนั้นไม่ได้ cache อยู่แล้ว)"""
    response = await call_next(request)
    path = request.url.path
    if not path.startswith("/api") and not path.startswith("/ocpp"):
        response.headers["Cache-Control"] = "no-cache"
    return response


@app.on_event("startup")
async def on_startup():
    init_db()
    seed_defaults()
    logger.info("Database พร้อมใช้งาน")
    asyncio.create_task(scheduled_backup_loop())


def get_current_user(access_token: Optional[str] = Cookie(default=None)) -> dict:
    payload = decode_access_token(access_token) if access_token else None
    if not payload:
        raise HTTPException(status_code=401, detail="กรุณาเข้าสู่ระบบก่อน")
    return payload


def require_role(*roles: str):
    def _dependency(user: dict = Depends(get_current_user)) -> dict:
        if user["role"] not in roles:
            raise HTTPException(status_code=403, detail="ไม่มีสิทธิ์เข้าถึงส่วนนี้")
        return user

    return _dependency


require_admin = require_role("admin")
require_staff_or_admin = require_role("staff", "admin")


# ============================================================
# WebSocket adapter: ทำให้ FastAPI WebSocket ใช้กับ python-ocpp ได้
# (python-ocpp คาดหวัง object ที่มี recv()/send() และ iterate ได้แบบ async)
# ============================================================
class FastAPIWebSocketAdapter:
    def __init__(self, websocket: WebSocket):
        self.websocket = websocket

    async def recv(self):
        return await self.websocket.receive_text()

    async def send(self, message: str):
        await self.websocket.send_text(message)

    def __aiter__(self):
        return self

    async def __anext__(self):
        try:
            return await self.recv()
        except WebSocketDisconnect as exc:
            raise StopAsyncIteration from exc


@app.websocket("/ocpp/{charge_point_id}")
async def ocpp_websocket(websocket: WebSocket, charge_point_id: str):
    # เครื่องชาร์จ OCPP 1.6J ต้องส่ง Sec-WebSocket-Protocol: ocpp1.6 มาด้วย
    requested = websocket.headers.get("sec-websocket-protocol", "")
    subprotocol = "ocpp1.6" if "ocpp1.6" in requested else None
    await websocket.accept(subprotocol=subprotocol)

    adapter = FastAPIWebSocketAdapter(websocket)
    cp = ChargePoint(charge_point_id, adapter)
    CONNECTED_CHARGE_POINTS[charge_point_id] = cp

    logger.info("เครื่องชาร์จเชื่อมต่อ: %s", charge_point_id)
    try:
        await cp.start()
    except WebSocketDisconnect:
        pass
    except Exception:
        logger.exception("เกิดข้อผิดพลาดกับการเชื่อมต่อของ %s", charge_point_id)
    finally:
        CONNECTED_CHARGE_POINTS.pop(charge_point_id, None)
        cleanup_charge_point(charge_point_id)
        db = SessionLocal()
        try:
            row = db.get(ChargePointDB, charge_point_id)
            if row:
                row.is_online = False
                db.commit()
        finally:
            db.close()
        logger.info("เครื่องชาร์จหลุดการเชื่อมต่อ: %s", charge_point_id)


# ============================================================
# REST API สำหรับ Dashboard
# ============================================================

@app.get("/api/charge-points")
def list_charge_points(user: dict = Depends(get_current_user)):
    db = SessionLocal()
    try:
        cp_query = db.query(ChargePointDB)
        my_tags: list[str] = []
        if user["role"] == "customer":
            my_tags = [
                c.card_uid
                for c in db.query(RFIDCardDB).filter(RFIDCardDB.user_id == int(user["sub"])).all()
            ]
            my_cp_ids = {
                cp_id
                for (cp_id,) in db.query(TransactionDB.charge_point_id)
                .filter(TransactionDB.id_tag.in_(my_tags))
                .distinct()
                .all()
            }
            cp_query = cp_query.filter(ChargePointDB.id.in_(my_cp_ids))
        rows = cp_query.all()
        active_txn_by_cp = {
            t.charge_point_id: t
            for t in db.query(TransactionDB).filter(TransactionDB.status == "Active").all()
        }
        now = datetime.utcnow()
        result = []
        for r in rows:
            # ถือว่า offline ถ้าไม่มี heartbeat มากกว่า 90 วิ แม้ flag is_online จะยังเป็น True
            online = bool(r.is_online) and r.last_seen and (now - r.last_seen) < timedelta(seconds=90)
            active_txn = active_txn_by_cp.get(r.id)
            result.append(
                {
                    "id": r.id,
                    "vendor": r.vendor,
                    "model": r.model,
                    "firmware_version": r.firmware_version,
                    "status": r.status,
                    "error_code": r.error_code,
                    "connector_id": r.connector_id,
                    "is_online": online,
                    "last_heartbeat": r.last_heartbeat,
                    "last_seen": r.last_seen,
                    "active_transaction_id": active_txn.id if active_txn is not None else None,
                    "active_transaction": (
                        {
                            "id": active_txn.id,
                            "id_tag": active_txn.id_tag,
                            "meter_start": active_txn.meter_start,
                            "start_time": active_txn.start_time,
                            "budget": active_txn.budget,
                            "is_mine": (
                                active_txn.id_tag in my_tags
                                if user["role"] == "customer"
                                else True
                            ),
                        }
                        if active_txn is not None
                        else None
                    ),
                    "live": _live_meter_snapshot(db, active_txn.id) if active_txn is not None else None,
                }
            )
        return result
    finally:
        db.close()


MEASURAND_FIELD_MAP = {
    "Energy.Active.Import.Register": "energy_wh",
    "Power.Active.Import": "power_w",
    "Voltage": "voltage_v",
    "Current.Import": "current_a",
    "Temperature": "temperature_c",
}


def _live_meter_snapshot(db, transaction_id: int) -> Optional[dict]:
    """ค่าไฟฟ้าล่าสุดของ transaction ที่กำลัง Active อยู่ (ค่าล่าสุดต่อ measurand)
    ใช้แสดงหน้า "กำลังชาร์จตอนนี้" คล้ายแอปของผู้ผลิต"""
    rows = (
        db.query(MeterValueDB)
        .filter(MeterValueDB.transaction_id == transaction_id)
        .order_by(MeterValueDB.id.desc())
        .limit(50)
        .all()
    )
    if not rows:
        return None

    snapshot: dict = {"last_update": None}
    for row in rows:
        field = MEASURAND_FIELD_MAP.get(row.measurand)
        if field is None or field in snapshot:
            continue
        snapshot[field] = row.value
        if snapshot["last_update"] is None:
            snapshot["last_update"] = row.timestamp
    return snapshot


@app.get("/api/charge-points/{charge_point_id}")
def get_charge_point(charge_point_id: str, user: dict = Depends(get_current_user)):
    db = SessionLocal()
    try:
        r = db.get(ChargePointDB, charge_point_id)
        if r is None:
            raise HTTPException(status_code=404, detail="ไม่พบเครื่องชาร์จนี้")

        now = datetime.utcnow()
        online = bool(r.is_online) and r.last_seen and (now - r.last_seen) < timedelta(seconds=90)

        txns = (
            db.query(TransactionDB)
            .filter(TransactionDB.charge_point_id == charge_point_id)
            .order_by(TransactionDB.id.desc())
            .limit(10)
            .all()
        )

        active_txn = next((t for t in txns if t.status == "Active"), None)
        live = _live_meter_snapshot(db, active_txn.id) if active_txn is not None else None

        return {
            "id": r.id,
            "vendor": r.vendor,
            "model": r.model,
            "firmware_version": r.firmware_version,
            "status": r.status,
            "error_code": r.error_code,
            "connector_id": r.connector_id,
            "is_online": online,
            "last_heartbeat": r.last_heartbeat,
            "last_seen": r.last_seen,
            "active_transaction": (
                {
                    "id": active_txn.id,
                    "id_tag": active_txn.id_tag,
                    "meter_start": active_txn.meter_start,
                    "start_time": active_txn.start_time,
                }
                if active_txn is not None
                else None
            ),
            "live": live,
            "recent_transactions": [
                {
                    "id": t.id,
                    "charge_point_id": t.charge_point_id,
                    "connector_id": t.connector_id,
                    "id_tag": t.id_tag,
                    "meter_start": t.meter_start,
                    "meter_stop": t.meter_stop,
                    "start_time": t.start_time,
                    "stop_time": t.stop_time,
                    "status": t.status,
                    "energy_kwh": (
                        round((t.meter_stop - t.meter_start) / 1000, 3)
                        if t.meter_stop is not None
                        else None
                    ),
                }
                for t in txns
            ],
        }
    finally:
        db.close()


@app.get("/api/transactions")
def list_transactions(
    charge_point_id: Optional[str] = None,
    limit: int = 50,
    user: dict = Depends(get_current_user),
):
    db = SessionLocal()
    try:
        query = db.query(TransactionDB)
        if charge_point_id:
            query = query.filter(TransactionDB.charge_point_id == charge_point_id)
        if user["role"] == "customer":
            my_tags = [
                c.card_uid
                for c in db.query(RFIDCardDB).filter(RFIDCardDB.user_id == int(user["sub"])).all()
            ]
            query = query.filter(TransactionDB.id_tag.in_(my_tags))
        rows = query.order_by(TransactionDB.id.desc()).limit(limit).all()

        cards_by_uid = {c.card_uid: c for c in db.query(RFIDCardDB).all()}
        users_by_id = {u.id: u for u in db.query(UserDB).all()}

        def user_name_for(id_tag: str) -> Optional[str]:
            card = cards_by_uid.get(id_tag)
            if card is None or card.user_id is None:
                return None
            owner = users_by_id.get(card.user_id)
            return (owner.full_name or owner.username) if owner else None

        return [
            {
                "id": t.id,
                "charge_point_id": t.charge_point_id,
                "connector_id": t.connector_id,
                "id_tag": t.id_tag,
                "user_name": user_name_for(t.id_tag),
                "meter_start": t.meter_start,
                "meter_stop": t.meter_stop,
                "start_time": t.start_time,
                "stop_time": t.stop_time,
                "status": t.status,
                "energy_kwh": (
                    round((t.meter_stop - t.meter_start) / 1000, 3)
                    if t.meter_stop is not None
                    else None
                ),
                "amount_due": t.amount_due,
                "budget": t.budget,
            }
            for t in rows
        ]
    finally:
        db.close()


@app.get("/api/events")
def list_events(
    charge_point_id: Optional[str] = None,
    limit: int = 100,
    user: dict = Depends(get_current_user),
):
    db = SessionLocal()
    try:
        query = db.query(EventLogDB)
        if charge_point_id:
            query = query.filter(EventLogDB.charge_point_id == charge_point_id)
        rows = query.order_by(EventLogDB.id.desc()).limit(limit).all()
        return [
            {
                "id": e.id,
                "charge_point_id": e.charge_point_id,
                "action": e.action,
                "payload": e.payload,
                "timestamp": e.timestamp,
            }
            for e in rows
        ]
    finally:
        db.close()


class RemoteStartRequest(BaseModel):
    id_tag: str
    connector_id: int = 1
    budget: Optional[float] = None  # งบ (บาท) สำหรับ session นี้ ไม่ส่ง = ใช้ยอด wallet ทั้งหมด


class RemoteStopRequest(BaseModel):
    transaction_id: int


class ResetRequest(BaseModel):
    type: str = "Soft"  # "Soft" หรือ "Hard"


def _get_connected_cp(charge_point_id: str) -> ChargePoint:
    cp = CONNECTED_CHARGE_POINTS.get(charge_point_id)
    if cp is None:
        raise HTTPException(status_code=404, detail="เครื่องชาร์จนี้ไม่ได้เชื่อมต่ออยู่ตอนนี้")
    return cp


def _require_response(response):
    if response is None:
        raise HTTPException(
            status_code=502,
            detail="เครื่องชาร์จตอบกลับข้อผิดพลาด (CallError) ไม่ทราบสถานะที่แน่ชัด",
        )
    return response


async def _call_charger(coro):
    """ส่งคำสั่งไปเครื่องชาร์จแล้วแปลง timeout/response ที่ไม่ตรงสเปค OCPP (เครื่องบางรุ่นตอบค่า
    enum ที่ไม่ได้อยู่ในสเปคจริง เช่น UnlockConnector.conf คืนค่า status ที่ไม่ใช่ Unlocked/
    UnlockFailed/NotSupported) ให้เป็น error message ที่อ่านได้ แทนที่จะปล่อยเป็น 500 เฉยๆ"""
    try:
        return _require_response(await coro)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="เครื่องชาร์จไม่ตอบสนอง (timeout)")
    except OCPPError as exc:
        raise HTTPException(status_code=502, detail=f"เครื่องชาร์จตอบกลับข้อผิดพลาด: {exc}")


def _reject_if_charging(charge_point_id: str) -> None:
    """กันไม่ให้สั่ง ChangeAvailability/UnlockConnector ระหว่างกำลังชาร์จจริงอยู่ เพราะเจอมาแล้วว่า
    เครื่องบางรุ่นจะหลุด transaction ที่กำลัง Charging อยู่โดยไม่ส่ง StopTransaction มาปิดให้ถูกต้อง
    แล้วเข้าสู่ loop พยายาม StartTransaction ใหม่ไปเรื่อยๆ โดยไม่จ่ายไฟจริงอีกเลย"""
    db = SessionLocal()
    try:
        cp_row = db.get(ChargePointDB, charge_point_id)
    finally:
        db.close()
    if cp_row is not None and cp_row.status == "Charging":
        raise HTTPException(
            status_code=409,
            detail="เครื่องกำลังชาร์จอยู่ ห้ามสั่งล็อค/ปลดล็อคหรือปลดล็อคหัวชาร์จตอนนี้ (จะทำให้เครื่องหลุด session แล้วชาร์จไม่เข้าอีก) กรุณารอให้ชาร์จเสร็จก่อน",
        )


def _log_remote_command(charge_point_id: str, action: str, payload: dict, username: str) -> None:
    db = SessionLocal()
    try:
        log_event(db, charge_point_id, action, {**payload, "triggered_by": username})
    finally:
        db.close()


@app.post("/api/charge-points/{charge_point_id}/remote-start")
async def remote_start(
    charge_point_id: str,
    body: RemoteStartRequest,
    user: dict = Depends(require_staff_or_admin),
):
    db = SessionLocal()
    try:
        auth_status, card = resolve_card_authorization(db, body.id_tag)
        if auth_status == "Accepted" and body.budget is not None:
            owner = db.get(UserDB, card.user_id) if card and card.user_id else None
            if owner is not None:
                owner.next_session_budget = min(body.budget, owner.wallet_balance)
                db.commit()
    finally:
        db.close()
    if auth_status != "Accepted":
        raise HTTPException(
            status_code=403,
            detail=f"idTag '{body.id_tag}' ยังไม่ได้ลงทะเบียน/ถูกระงับ หรือยอดเงินใน wallet หมด ไม่อนุญาตให้เริ่มชาร์จ",
        )

    cp = _get_connected_cp(charge_point_id)
    response = await _call_charger(cp.remote_start_transaction(body.id_tag, body.connector_id))
    _log_remote_command(
        charge_point_id,
        "RemoteStartTransaction",
        {"id_tag": body.id_tag, "connector_id": body.connector_id, "status": response.status},
        user["username"],
    )
    return {"status": response.status}


@app.post("/api/charge-points/{charge_point_id}/self-start")
async def self_start(
    charge_point_id: str,
    connector_id: int = 1,
    user: dict = Depends(get_current_user),
):
    """ให้ลูกค้าที่ไม่มีบัตร RFID กดเริ่มชาร์จเองผ่านแอปได้ โดยผูกกับ wallet ของตัวเอง —
    สร้างบัตรเสมือน (virtual card, card_uid = APP-{user_id}) ให้อัตโนมัติถ้ายังไม่มี แล้วใช้กลไก
    เดิมทั้งหมด (resolve_card_authorization, budget, หักเงิน wallet ตอนจบ) เหมือนบัตรจริงทุกอย่าง"""
    db = SessionLocal()
    try:
        row = db.get(UserDB, int(user["sub"]))
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")

        active = (
            db.query(TransactionDB)
            .filter(TransactionDB.charge_point_id == charge_point_id, TransactionDB.status == "Active")
            .first()
        )
        if active is not None:
            raise HTTPException(status_code=409, detail="เครื่องนี้กำลังมีคนชาร์จอยู่ กรุณารอให้ว่างก่อน")

        card = (
            db.query(RFIDCardDB)
            .filter(RFIDCardDB.user_id == row.id, RFIDCardDB.card_uid == f"APP-{row.id}")
            .first()
        )
        if card is None:
            card = RFIDCardDB(card_uid=f"APP-{row.id}", user_id=row.id, is_active=True, balance=0)
            db.add(card)
            db.commit()
            db.refresh(card)
        id_tag = card.card_uid

        auth_status, _card = resolve_card_authorization(db, id_tag)
    finally:
        db.close()
    if auth_status != "Accepted":
        raise HTTPException(status_code=403, detail="ยอดเงินใน wallet ไม่พอ หรือบัญชีถูกระงับ ไม่อนุญาตให้เริ่มชาร์จ")

    cp = _get_connected_cp(charge_point_id)
    response = await _call_charger(cp.remote_start_transaction(id_tag, connector_id))
    _log_remote_command(
        charge_point_id,
        "RemoteStartTransaction",
        {"id_tag": id_tag, "connector_id": connector_id, "status": response.status, "self_service": True},
        user["username"],
    )
    return {"status": response.status}


@app.post("/api/charge-points/{charge_point_id}/remote-stop")
async def remote_stop(
    charge_point_id: str,
    body: RemoteStopRequest,
    user: dict = Depends(get_current_user),
):
    if user["role"] == "customer":
        db = SessionLocal()
        try:
            txn = db.get(TransactionDB, body.transaction_id)
            owns_tag = txn is not None and (
                db.query(RFIDCardDB)
                .filter(RFIDCardDB.user_id == int(user["sub"]), RFIDCardDB.card_uid == txn.id_tag)
                .first()
                is not None
            )
        finally:
            db.close()
        if not owns_tag:
            raise HTTPException(status_code=403, detail="คุณไม่มีสิทธิ์หยุดชาร์จรายการนี้")
    elif user["role"] not in ("staff", "admin"):
        raise HTTPException(status_code=403, detail="ไม่มีสิทธิ์เข้าถึงส่วนนี้")

    cp = _get_connected_cp(charge_point_id)
    response = await _call_charger(cp.remote_stop_transaction(body.transaction_id))
    _log_remote_command(
        charge_point_id,
        "RemoteStopTransaction",
        {"transaction_id": body.transaction_id, "status": response.status},
        user["username"],
    )
    return {"status": response.status}


@app.post("/api/charge-points/{charge_point_id}/unlock")
async def unlock(
    charge_point_id: str,
    connector_id: int = 1,
    user: dict = Depends(require_staff_or_admin),
):
    _reject_if_charging(charge_point_id)
    cp = _get_connected_cp(charge_point_id)
    response = await _call_charger(cp.unlock_connector(connector_id))
    _log_remote_command(
        charge_point_id,
        "UnlockConnector",
        {"connector_id": connector_id, "status": response.status},
        user["username"],
    )
    return {"status": response.status}


@app.post("/api/charge-points/{charge_point_id}/reset")
async def reset(
    charge_point_id: str,
    body: ResetRequest,
    user: dict = Depends(require_staff_or_admin),
):
    cp = _get_connected_cp(charge_point_id)
    response = await _call_charger(cp.reset(body.type))
    _log_remote_command(
        charge_point_id,
        "Reset",
        {"type": body.type, "status": response.status},
        user["username"],
    )
    return {"status": response.status}


class ChangeAvailabilityRequest(BaseModel):
    connector_id: int = 1
    type: str  # "Operative" หรือ "Inoperative"


@app.post("/api/charge-points/{charge_point_id}/change-availability")
async def change_availability(
    charge_point_id: str,
    body: ChangeAvailabilityRequest,
    user: dict = Depends(require_admin),
):
    """ปลด/ล็อคเครื่องด้วยมือ (ทางออกฉุกเฉินเผื่อระบบล็อคอัตโนมัติค้าง หรือให้ admin คุมเองโดยตรง)"""
    _reject_if_charging(charge_point_id)
    cp = _get_connected_cp(charge_point_id)
    response = await _call_charger(cp.change_availability(body.connector_id, body.type))
    _log_remote_command(
        charge_point_id,
        "ChangeAvailability",
        {"connector_id": body.connector_id, "type": body.type, "status": response.status},
        user["username"],
    )
    return {"status": response.status}


class ChangeConfigurationRequest(BaseModel):
    key: str
    value: str


@app.get("/api/charge-points/{charge_point_id}/configuration")
async def get_configuration(
    charge_point_id: str,
    user: dict = Depends(require_admin),
):
    cp = _get_connected_cp(charge_point_id)
    try:
        response = await cp.get_configuration()
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="เครื่องชาร์จไม่ตอบสนอง (timeout)")
    except OCPPError as exc:
        raise HTTPException(status_code=502, detail=f"เครื่องชาร์จตอบกลับข้อผิดพลาด: {exc}")
    return {
        "configuration_key": response.configuration_key or [],
        "unknown_key": response.unknown_key or [],
    }


@app.post("/api/charge-points/{charge_point_id}/configuration")
async def change_configuration(
    charge_point_id: str,
    body: ChangeConfigurationRequest,
    user: dict = Depends(require_admin),
):
    cp = _get_connected_cp(charge_point_id)
    try:
        response = await cp.change_configuration(body.key, body.value)
    except asyncio.TimeoutError:
        raise HTTPException(status_code=504, detail="เครื่องชาร์จไม่ตอบสนอง (timeout)")
    except OCPPError as exc:
        raise HTTPException(status_code=502, detail=f"เครื่องชาร์จตอบกลับข้อผิดพลาด: {exc}")

    db = SessionLocal()
    try:
        log_event(
            db,
            charge_point_id,
            "ChangeConfiguration",
            {
                "key": body.key,
                "value": body.value,
                "status": response.status,
                "changed_by": user["username"],
            },
        )
    finally:
        db.close()
    return {"status": response.status}


@app.get("/api/health")
def health():
    return {"status": "ok"}


@app.get("/api/settings")
def public_settings():
    """ค่าตั้งค่าที่หน้า dashboard หลักใช้แสดงผล (ไม่ต้อง login)"""
    db = SessionLocal()
    try:
        s = get_settings(db)
        latest = db.query(ChangelogDB).order_by(ChangelogDB.id.desc()).first()
        return {
            "system_name": s.system_name,
            "latest_version": latest.version if latest else None,
            "price_per_kwh": s.price_per_kwh,
            "allow_customer_mock_topup": s.allow_customer_mock_topup,
        }
    finally:
        db.close()


# ============================================================
# Auth
# ============================================================


class LoginRequest(BaseModel):
    username: str
    password: str


class RegisterRequest(BaseModel):
    username: str
    password: str
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None


def _set_access_token_cookie(response: Response, user_row: UserDB) -> None:
    token = create_access_token(user_row.id, user_row.username, user_row.role)
    response.set_cookie(
        ACCESS_TOKEN_COOKIE_NAME,
        token,
        httponly=True,
        samesite="lax",
        max_age=60 * 60 * 24 * ACCESS_TOKEN_EXPIRE_DAYS,
    )


@app.post("/api/auth/login")
def auth_login(body: LoginRequest, response: Response):
    db = SessionLocal()
    try:
        user_row = db.query(UserDB).filter(UserDB.username == body.username).first()
        if not user_row or not user_row.is_active or not verify_password(body.password, user_row.password_hash):
            raise HTTPException(status_code=401, detail="username หรือ password ไม่ถูกต้อง")

        if is_legacy_hash(user_row.password_hash):
            user_row.password_hash = hash_password(body.password)
            db.commit()

        _set_access_token_cookie(response, user_row)
        return {"id": user_row.id, "username": user_row.username, "role": user_row.role}
    finally:
        db.close()


@app.post("/api/auth/register")
def auth_register(body: RegisterRequest, response: Response):
    db = SessionLocal()
    try:
        if db.query(UserDB).filter(UserDB.username == body.username).first():
            raise HTTPException(status_code=409, detail="username นี้มีคนใช้แล้ว")

        user_row = UserDB(
            username=body.username,
            password_hash=hash_password(body.password),
            full_name=body.full_name,
            email=body.email,
            phone=body.phone,
            role="customer",
            is_active=True,
        )
        db.add(user_row)
        db.commit()
        db.refresh(user_row)

        _set_access_token_cookie(response, user_row)
        return {"id": user_row.id, "username": user_row.username, "role": user_row.role}
    finally:
        db.close()


@app.post("/api/auth/logout")
def auth_logout(response: Response):
    response.delete_cookie(ACCESS_TOKEN_COOKIE_NAME)
    return {"status": "ok"}


@app.get("/api/auth/me")
def auth_me(user: dict = Depends(get_current_user)):
    db = SessionLocal()
    try:
        row = db.get(UserDB, int(user["sub"]))
        wallet_balance = row.wallet_balance if row else None
        next_session_budget = row.next_session_budget if row else None
    finally:
        db.close()
    return {
        "id": int(user["sub"]),
        "username": user["username"],
        "role": user["role"],
        "wallet_balance": wallet_balance,
        "next_session_budget": next_session_budget,
    }


class MyBudgetRequest(BaseModel):
    budget: Optional[float] = None


@app.post("/api/me/budget")
def set_my_budget(body: MyBudgetRequest, user: dict = Depends(get_current_user)):
    db = SessionLocal()
    try:
        row = db.get(UserDB, int(user["sub"]))
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")
        if body.budget is not None:
            if body.budget <= 0:
                raise HTTPException(status_code=400, detail="งบต้องมากกว่า 0")
            row.next_session_budget = min(body.budget, row.wallet_balance)
        else:
            row.next_session_budget = None
        db.commit()
        return {"next_session_budget": row.next_session_budget}
    finally:
        db.close()


class MyWalletTopupRequest(BaseModel):
    amount: float


class MockWalletPaymentRequest(BaseModel):
    amount: float


def _serialize_wallet_payment(payment: WalletPaymentDB) -> dict:
    return {
        "id": payment.id,
        "reference": payment.reference,
        "amount": payment.amount,
        "method": payment.method,
        "provider": payment.provider,
        "status": payment.status,
        "provider_payment_id": payment.provider_payment_id,
        "created_at": payment.created_at,
        "completed_at": payment.completed_at,
    }


@app.post("/api/me/wallet/mock-payment")
def create_mock_wallet_payment(body: MockWalletPaymentRequest, user: dict = Depends(get_current_user)):
    """สร้างรายการเติมเงินจำลอง โดยยังไม่เพิ่มยอดจนกว่าจะกดจำลองสแกนสำเร็จ"""
    if body.amount <= 0 or body.amount > 100000:
        raise HTTPException(status_code=400, detail="จำนวนเงินต้องอยู่ระหว่าง 0.01 ถึง 100,000 บาท")

    db = SessionLocal()
    try:
        if not get_settings(db).allow_customer_mock_topup:
            raise HTTPException(status_code=403, detail="ยังไม่ได้เปิดโหมดเติมเงินจำลอง")
        if not db.get(UserDB, int(user["sub"])):
            raise HTTPException(status_code=404, detail="ไม่พบ user")

        payment = WalletPaymentDB(
            reference=f"MOCK-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{uuid4().hex[:6].upper()}",
            user_id=int(user["sub"]),
            amount=round(body.amount, 2),
            method="promptpay",
            provider="mock",
            status="pending",
        )
        db.add(payment)
        db.commit()
        db.refresh(payment)
        return _serialize_wallet_payment(payment)
    finally:
        db.close()


@app.post("/api/me/wallet/mock-payment/{payment_id}/complete")
def complete_mock_wallet_payment(payment_id: int, user: dict = Depends(get_current_user)):
    """จำลองผลสำเร็จจาก QR และเครดิต Wallet แบบ idempotent"""
    db = SessionLocal()
    try:
        payment = (
            db.query(WalletPaymentDB)
            .filter(WalletPaymentDB.id == payment_id, WalletPaymentDB.user_id == int(user["sub"]))
            .first()
        )
        if not payment:
            raise HTTPException(status_code=404, detail="ไม่พบรายการเติมเงิน")

        row = db.get(UserDB, int(user["sub"]))
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")

        if payment.status == "successful":
            return {
                **_serialize_wallet_payment(payment),
                "wallet_balance": row.wallet_balance,
                "credited": False,
            }
        if payment.status != "pending":
            raise HTTPException(status_code=409, detail="รายการนี้ไม่อยู่ในสถานะรอชำระเงิน")

        payment.status = "successful"
        payment.provider_payment_id = f"mock_charge_{uuid4().hex[:12]}"
        payment.completed_at = datetime.utcnow()
        row.wallet_balance += payment.amount
        db.add(WalletLedgerDB(
            user_id=row.id,
            amount=payment.amount,
            reason="topup",
            note=f"mock payment {payment.reference}",
            created_by=user["username"],
        ))
        db.commit()
        db.refresh(payment)
        return {
            **_serialize_wallet_payment(payment),
            "wallet_balance": row.wallet_balance,
            "credited": True,
        }
    finally:
        db.close()


@app.post("/api/me/wallet/topup")
def self_wallet_topup(body: MyWalletTopupRequest, user: dict = Depends(get_current_user)):
    """เติมเงินเข้า wallet ของตัวเอง (โหมดทดสอบ ยังไม่ผูก payment gateway จริง เงินไม่ได้เคลื่อนไหวจริง)
    ต้องเปิด SettingsDB.allow_customer_mock_topup ไว้ก่อนถึงจะใช้ได้"""
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="จำนวนเงินต้องมากกว่า 0")
    db = SessionLocal()
    try:
        if not get_settings(db).allow_customer_mock_topup:
            raise HTTPException(status_code=403, detail="ยังไม่เปิดให้เติมเงินเองในโหมดนี้ กรุณาติดต่อผู้ดูแลระบบ")
        row = db.get(UserDB, int(user["sub"]))
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")
        row.wallet_balance += body.amount
        db.add(WalletLedgerDB(
            user_id=row.id,
            amount=body.amount,
            reason="topup",
            note="self-service mock top-up",
            created_by=user["username"],
        ))
        db.commit()
        return {"wallet_balance": row.wallet_balance}
    finally:
        db.close()


# ============================================================
# Admin: Settings
# ============================================================


class SettingsUpdateRequest(BaseModel):
    system_name: str
    heartbeat_interval: int
    auto_accept_authorize: bool
    lock_connector_until_authorized: bool = False
    price_per_kwh: float = 7.0
    allow_customer_mock_topup: bool = False


@app.get("/api/admin/settings")
def admin_get_settings(user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        s = get_settings(db)
        return {
            "system_name": s.system_name,
            "heartbeat_interval": s.heartbeat_interval,
            "auto_accept_authorize": s.auto_accept_authorize,
            "lock_connector_until_authorized": s.lock_connector_until_authorized,
            "price_per_kwh": s.price_per_kwh,
            "allow_customer_mock_topup": s.allow_customer_mock_topup,
        }
    finally:
        db.close()


@app.put("/api/admin/settings")
def admin_update_settings(body: SettingsUpdateRequest, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        s = get_settings(db)
        s.system_name = body.system_name
        s.heartbeat_interval = body.heartbeat_interval
        s.auto_accept_authorize = body.auto_accept_authorize
        s.lock_connector_until_authorized = body.lock_connector_until_authorized
        s.price_per_kwh = body.price_per_kwh
        s.allow_customer_mock_topup = body.allow_customer_mock_topup
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ============================================================
# Admin: Change Log
# ============================================================


class ChangelogCreateRequest(BaseModel):
    version: str
    description: str


@app.get("/api/admin/changelog")
def admin_list_changelog(user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        rows = db.query(ChangelogDB).order_by(ChangelogDB.id.desc()).all()
        return [
            {
                "id": r.id,
                "version": r.version,
                "description": r.description,
                "created_at": r.created_at,
            }
            for r in rows
        ]
    finally:
        db.close()


@app.post("/api/admin/changelog")
def admin_add_changelog(body: ChangelogCreateRequest, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        entry = ChangelogDB(version=body.version, description=body.description)
        db.add(entry)
        db.commit()
        db.refresh(entry)
        return {"id": entry.id}
    finally:
        db.close()


@app.delete("/api/admin/changelog/{entry_id}")
def admin_delete_changelog(entry_id: int, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        entry = db.get(ChangelogDB, entry_id)
        if entry:
            db.delete(entry)
            db.commit()
        return {"status": "ok"}
    finally:
        db.close()


# ============================================================
# Admin: User management
# ============================================================


class UserCreateRequest(BaseModel):
    username: str
    password: str
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    role: str = "customer"


class UserUpdateRequest(BaseModel):
    full_name: Optional[str] = None
    email: Optional[str] = None
    phone: Optional[str] = None
    role: str
    is_active: bool
    password: Optional[str] = None  # ถ้าส่งมาจะ reset รหัสผ่านใหม่


def _serialize_user(u: UserDB) -> dict:
    return {
        "id": u.id,
        "username": u.username,
        "full_name": u.full_name,
        "email": u.email,
        "phone": u.phone,
        "role": u.role,
        "is_active": u.is_active,
        "wallet_balance": u.wallet_balance,
        "next_session_budget": u.next_session_budget,
        "created_at": u.created_at,
    }


VALID_ROLES = {"admin", "staff", "customer"}


@app.get("/api/admin/users")
def admin_list_users(role: Optional[str] = None, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        query = db.query(UserDB)
        if role:
            query = query.filter(UserDB.role == role)
        rows = query.order_by(UserDB.id.desc()).all()
        return [_serialize_user(u) for u in rows]
    finally:
        db.close()


@app.post("/api/admin/users")
def admin_create_user(body: UserCreateRequest, user: dict = Depends(require_admin)):
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"role ต้องเป็นหนึ่งใน {VALID_ROLES}")
    db = SessionLocal()
    try:
        if db.query(UserDB).filter(UserDB.username == body.username).first():
            raise HTTPException(status_code=409, detail="username นี้มีคนใช้แล้ว")
        row = UserDB(
            username=body.username,
            password_hash=hash_password(body.password),
            full_name=body.full_name,
            email=body.email,
            phone=body.phone,
            role=body.role,
            is_active=True,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return _serialize_user(row)
    finally:
        db.close()


@app.get("/api/admin/users/{user_id}")
def admin_get_user(user_id: int, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        row = db.get(UserDB, user_id)
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")
        return _serialize_user(row)
    finally:
        db.close()


@app.put("/api/admin/users/{user_id}")
def admin_update_user(user_id: int, body: UserUpdateRequest, user: dict = Depends(require_admin)):
    if body.role not in VALID_ROLES:
        raise HTTPException(status_code=400, detail=f"role ต้องเป็นหนึ่งใน {VALID_ROLES}")
    db = SessionLocal()
    try:
        row = db.get(UserDB, user_id)
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")
        row.full_name = body.full_name
        row.email = body.email
        row.phone = body.phone
        row.role = body.role
        row.is_active = body.is_active
        if body.password:
            row.password_hash = hash_password(body.password)
        db.commit()
        return _serialize_user(row)
    finally:
        db.close()


@app.patch("/api/admin/users/{user_id}/deactivate")
def admin_deactivate_user(user_id: int, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        row = db.get(UserDB, user_id)
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")
        row.is_active = False
        db.commit()
        return {"status": "ok"}
    finally:
        db.close()


class WalletTopupRequest(BaseModel):
    amount: float
    note: Optional[str] = None


@app.post("/api/admin/users/{user_id}/wallet/topup")
def admin_wallet_topup(user_id: int, body: WalletTopupRequest, user: dict = Depends(require_admin)):
    if body.amount <= 0:
        raise HTTPException(status_code=400, detail="จำนวนเงินต้องมากกว่า 0")
    db = SessionLocal()
    try:
        row = db.get(UserDB, user_id)
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบ user")
        row.wallet_balance += body.amount
        db.add(WalletLedgerDB(
            user_id=row.id,
            amount=body.amount,
            reason="topup",
            note=body.note,
            created_by=user["username"],
        ))
        db.commit()
        return _serialize_user(row)
    finally:
        db.close()


# ============================================================
# Admin: RFID card management
# ============================================================


class CardCreateRequest(BaseModel):
    card_uid: str
    user_id: int
    balance: float = 0


class CardUpdateRequest(BaseModel):
    user_id: int
    is_active: bool
    balance: float


def _serialize_card(c: RFIDCardDB) -> dict:
    return {
        "id": c.id,
        "card_uid": c.card_uid,
        "user_id": c.user_id,
        "is_active": c.is_active,
        "balance": c.balance,
        "created_at": c.created_at,
    }


@app.get("/api/admin/cards")
def admin_list_cards(user_id: Optional[int] = None, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        query = db.query(RFIDCardDB)
        if user_id:
            query = query.filter(RFIDCardDB.user_id == user_id)
        rows = query.order_by(RFIDCardDB.id.desc()).all()
        return [_serialize_card(c) for c in rows]
    finally:
        db.close()


@app.post("/api/admin/cards")
def admin_create_card(body: CardCreateRequest, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        if not db.get(UserDB, body.user_id):
            raise HTTPException(status_code=404, detail="ไม่พบ user ที่จะผูกบัตร")
        if db.query(RFIDCardDB).filter(RFIDCardDB.card_uid == body.card_uid).first():
            raise HTTPException(status_code=409, detail="card_uid นี้มีอยู่แล้ว")
        row = RFIDCardDB(card_uid=body.card_uid, user_id=body.user_id, balance=body.balance, is_active=True)
        db.add(row)
        db.commit()
        db.refresh(row)
        return _serialize_card(row)
    finally:
        db.close()


@app.put("/api/admin/cards/{card_id}")
def admin_update_card(card_id: int, body: CardUpdateRequest, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        row = db.get(RFIDCardDB, card_id)
        if not row:
            raise HTTPException(status_code=404, detail="ไม่พบบัตร")
        if not db.get(UserDB, body.user_id):
            raise HTTPException(status_code=404, detail="ไม่พบ user ที่จะผูกบัตร")
        row.user_id = body.user_id
        row.is_active = body.is_active
        row.balance = body.balance
        db.commit()
        return _serialize_card(row)
    finally:
        db.close()


@app.delete("/api/admin/cards/{card_id}")
def admin_delete_card(card_id: int, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        row = db.get(RFIDCardDB, card_id)
        if row:
            db.delete(row)
            db.commit()
        return {"status": "ok"}
    finally:
        db.close()


@app.get("/api/admin/card-taps")
def admin_list_card_taps(
    charge_point_id: Optional[str] = None,
    limit: int = 200,
    user: dict = Depends(require_admin),
):
    db = SessionLocal()
    try:
        query = db.query(CardTapDB)
        if charge_point_id:
            query = query.filter(CardTapDB.charge_point_id == charge_point_id)
        rows = query.order_by(CardTapDB.id.desc()).limit(limit).all()
        return [
            {
                "id": r.id,
                "charge_point_id": r.charge_point_id,
                "card_uid": r.card_uid,
                "user_id": r.user_id,
                "status": r.status,
                "created_at": r.created_at,
            }
            for r in rows
        ]
    finally:
        db.close()


# ============================================================
# Admin: Charge Points
# ============================================================


@app.delete("/api/admin/charge-points/{charge_point_id}")
def admin_delete_charge_point(charge_point_id: str, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        row = db.get(ChargePointDB, charge_point_id)
        if row:
            db.delete(row)
            db.commit()
            log_event(
                db,
                charge_point_id,
                "ChargePointDeleted",
                {"deleted_by": user["username"]},
            )
        return {"status": "ok"}
    finally:
        db.close()


# ============================================================
# Admin: Transactions
# ============================================================


@app.post("/api/admin/transactions/{transaction_id}/force-stop")
def admin_force_stop_transaction(transaction_id: int, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        txn = db.get(TransactionDB, transaction_id)
        if txn is None:
            raise HTTPException(status_code=404, detail="ไม่พบ transaction นี้")
        if txn.status != "Active":
            raise HTTPException(status_code=409, detail="Transaction นี้ไม่ได้อยู่ในสถานะ Active")

        txn.status = "Cancelled"
        txn.stop_time = datetime.utcnow()
        db.commit()
        log_event(
            db,
            txn.charge_point_id,
            "TransactionForceStopped",
            {"transaction_id": transaction_id, "stopped_by": user["username"]},
        )
        return {"status": "ok"}
    finally:
        db.close()


@app.delete("/api/admin/transactions/{transaction_id}")
def admin_delete_transaction(transaction_id: int, user: dict = Depends(require_admin)):
    db = SessionLocal()
    try:
        txn = db.get(TransactionDB, transaction_id)
        if txn:
            charge_point_id = txn.charge_point_id
            db.delete(txn)
            db.commit()
            log_event(
                db,
                charge_point_id,
                "TransactionDeleted",
                {"transaction_id": transaction_id, "deleted_by": user["username"]},
            )
        return {"status": "ok"}
    finally:
        db.close()


# ============================================================
# Admin: Backup
# ============================================================

BACKUP_FILENAME_RE = re.compile(r"^[\w.-]+\.db$")


def _safe_backup_path(filename: str) -> str:
    if not BACKUP_FILENAME_RE.match(filename):
        raise HTTPException(status_code=400, detail="ชื่อไฟล์ไม่ถูกต้อง")
    path = os.path.join(BACKUP_DIR, filename)
    if os.path.dirname(os.path.abspath(path)) != os.path.abspath(BACKUP_DIR):
        raise HTTPException(status_code=400, detail="ชื่อไฟล์ไม่ถูกต้อง")
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="ไม่พบไฟล์ backup นี้")
    return path


@app.get("/api/admin/backup/list")
def admin_list_backups(user: dict = Depends(require_admin)):
    return list_backups()


@app.get("/api/admin/backup/export")
def admin_export_backup(user: dict = Depends(require_admin)):
    path = create_backup(prefix="manual")
    return FileResponse(path, filename=os.path.basename(path), media_type="application/octet-stream")


@app.get("/api/admin/backup/download/{filename}")
def admin_download_backup(filename: str, user: dict = Depends(require_admin)):
    path = _safe_backup_path(filename)
    return FileResponse(path, filename=filename, media_type="application/octet-stream")


@app.post("/api/admin/backup/restore")
def admin_restore_backup(file: UploadFile = File(...), user: dict = Depends(require_admin)):
    with tempfile.NamedTemporaryFile(delete=False, suffix=".db") as tmp:
        tmp.write(file.file.read())
        tmp_path = tmp.name

    try:
        pre_restore_path = restore_from_file(tmp_path)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    finally:
        os.remove(tmp_path)

    db = SessionLocal()
    try:
        log_event(
            db,
            None,
            "DatabaseRestore",
            {
                "restored_by": user["username"],
                "uploaded_filename": file.filename,
                "pre_restore_backup": os.path.basename(pre_restore_path),
            },
        )
    finally:
        db.close()

    return {"status": "ok", "pre_restore_backup": os.path.basename(pre_restore_path)}


# เสิร์ฟหน้า dashboard (ต้องอยู่หลัง route อื่นๆ ทั้งหมด)
app.mount("/", StaticFiles(directory="app/static", html=True), name="static")
