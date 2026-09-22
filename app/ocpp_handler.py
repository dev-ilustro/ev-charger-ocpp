"""
Logic หลักของ OCPP 1.6J: รับ message จากเครื่องชาร์จ (Charge Point)
บันทึกสถานะลง DB และสามารถส่งคำสั่งกลับไปหาเครื่อง (Remote commands) ได้
"""

import asyncio
import json
import logging
from datetime import datetime, timedelta, timezone

from ocpp.routing import after, on
from ocpp.v16 import ChargePoint as CP
from ocpp.v16 import call, call_result
from ocpp.v16.enums import (
    Action,
    AuthorizationStatus,
    AvailabilityStatus,
    AvailabilityType,
    RegistrationStatus,
    RemoteStartStopStatus,
    ResetStatus,
    UnlockStatus,
)

from app.database import (
    CardTapDB,
    ChargePointDB,
    EventLogDB,
    MeterValueDB,
    RFIDCardDB,
    SessionLocal,
    TransactionDB,
    UserDB,
    WalletLedgerDB,
    get_settings,
    resolve_card_authorization,
)

logger = logging.getLogger("ocpp-handler")

# เก็บ instance ของ ChargePoint ที่เชื่อมต่ออยู่ตอนนี้ (ใน memory) เพื่อใช้ส่ง remote command
CONNECTED_CHARGE_POINTS: dict[str, "ChargePoint"] = {}

# เก็บ task ที่รอสั่งล็อคเครื่องคืนอัตโนมัติ (เผื่อแตะบัตรผ่านแล้วแต่ไม่เริ่มชาร์จจริง)
# key = charge_point_id
_RELOCK_TASKS: dict[str, asyncio.Task] = {}

# เวลารอ (วินาที) หลังแตะบัตรผ่าน ก่อนจะสั่งล็อคเครื่องคืนอัตโนมัติถ้ายังไม่เริ่ม transaction
REAUTHORIZE_TIMEOUT_SECONDS = 90


def _cancel_relock_task(charge_point_id: str) -> None:
    task = _RELOCK_TASKS.pop(charge_point_id, None)
    if task and not task.done():
        task.cancel()


def cleanup_charge_point(charge_point_id: str) -> None:
    """เรียกตอนเครื่องชาร์จหลุดการเชื่อมต่อ เพื่อยกเลิก background task ที่ค้างรอสั่งล็อคคืน"""
    _cancel_relock_task(charge_point_id)


def log_event(db, charge_point_id: str, action: str, payload: dict) -> None:
    entry = EventLogDB(
        charge_point_id=charge_point_id,
        action=action,
        payload=json.dumps(payload, default=str, ensure_ascii=False),
    )
    db.add(entry)
    db.commit()


def _upsert_charge_point(db, charge_point_id: str, **fields) -> ChargePointDB:
    cp_row = db.get(ChargePointDB, charge_point_id)
    if cp_row is None:
        cp_row = ChargePointDB(id=charge_point_id)
        db.add(cp_row)
    for key, value in fields.items():
        setattr(cp_row, key, value)
    cp_row.last_seen = datetime.utcnow()
    db.commit()
    return cp_row


class ChargePoint(CP):
    """แทนการเชื่อมต่อ WebSocket ของเครื่องชาร์จ 1 เครื่อง"""

    # ---------- Handlers: ข้อความที่เครื่องชาร์จส่งเข้ามา ----------

    @on(Action.boot_notification)
    async def on_boot_notification(self, charge_point_vendor, charge_point_model, **kwargs):
        db = SessionLocal()
        try:
            _upsert_charge_point(
                db,
                self.id,
                vendor=charge_point_vendor,
                model=charge_point_model,
                firmware_version=kwargs.get("firmware_version"),
                is_online=True,
            )
            log_event(db, self.id, "BootNotification", kwargs)
            heartbeat_interval = get_settings(db).heartbeat_interval
        finally:
            db.close()

        logger.info("BootNotification จาก %s: %s %s", self.id, charge_point_vendor, charge_point_model)
        return call_result.BootNotification(
            current_time=datetime.now(timezone.utc).isoformat(),
            interval=heartbeat_interval,
            status=RegistrationStatus.accepted,
        )

    @after(Action.boot_notification)
    async def after_boot_notification(self, **kwargs):
        # ล็อคเครื่อง (Inoperative) ทันทีที่ boot เสร็จ ถ้าเปิดโหมด "ล็อคจนกว่าจะแตะบัตร" ไว้
        # ต้องทำใน @after เท่านั้น เพราะการส่ง Call ใหม่ (ChangeAvailability) ระหว่างยังไม่ได้
        # ตอบ BootNotification.conf กลับไปจะทำให้ recv loop ของ python-ocpp ค้าง (deadlock)
        db = SessionLocal()
        try:
            enabled = get_settings(db).lock_connector_until_authorized
        finally:
            db.close()
        if enabled:
            await self._set_connector_lock(True)

    @on(Action.heartbeat)
    async def on_heartbeat(self, **kwargs):
        db = SessionLocal()
        try:
            _upsert_charge_point(db, self.id, last_heartbeat=datetime.utcnow(), is_online=True)
        finally:
            db.close()
        return call_result.Heartbeat(current_time=datetime.now(timezone.utc).isoformat())

    @on(Action.status_notification)
    async def on_status_notification(self, connector_id, error_code, status, **kwargs):
        db = SessionLocal()
        try:
            _upsert_charge_point(
                db,
                self.id,
                status=status,
                error_code=error_code,
                connector_id=connector_id,
                is_online=True,
            )
            log_event(db, self.id, "StatusNotification", {"connector_id": connector_id, "status": status, "error_code": error_code})
        finally:
            db.close()
        logger.info("StatusNotification %s: connector=%s status=%s", self.id, connector_id, status)
        return call_result.StatusNotification()

    @on(Action.authorize)
    async def on_authorize(self, id_tag, **kwargs):
        # เช็คบัตรจริงจากตาราง rfid_cards ก่อน ถ้าไม่พบบัตรเลยค่อย fallback ไปใช้
        # auto_accept_authorize (โหมด dev/bring-up ก่อนที่จะลงทะเบียนบัตรจริง)
        # ใช้กติกาเดียวกับตอน admin/staff กด Remote Start จากหน้าเว็บ (resolve_card_authorization)
        db = SessionLocal()
        try:
            status, card = resolve_card_authorization(db, id_tag)
            if card is None and status == AuthorizationStatus.accepted:
                logger.warning(
                    "Authorize %s: idTag=%s ไม่มีในระบบบัตร แต่ auto_accept_authorize เปิดอยู่ -> accept",
                    self.id,
                    id_tag,
                )
            db.add(
                CardTapDB(
                    charge_point_id=self.id,
                    card_uid=id_tag,
                    user_id=card.user_id if card is not None else None,
                    status=status,
                )
            )
            db.commit()
        finally:
            db.close()
        logger.info("Authorize %s: idTag=%s -> %s", self.id, id_tag, status)
        self._last_authorize_status = status
        if status == AuthorizationStatus.accepted:
            self._last_authorized_tag = id_tag
            self._last_authorized_at = datetime.utcnow()
        return call_result.Authorize(id_tag_info={"status": status})

    @after(Action.authorize)
    async def after_authorize(self, id_tag, **kwargs):
        # ปลดล็อคเครื่อง (Operative) หลังแตะบัตรผ่านแล้ว ถ้าเปิดโหมด "ล็อคจนกว่าจะแตะบัตร" ไว้
        # แล้วตั้งเวลาล็อคคืนอัตโนมัติเผื่อแตะบัตรแล้วไม่เริ่มชาร์จจริง
        if getattr(self, "_last_authorize_status", None) != AuthorizationStatus.accepted:
            return
        db = SessionLocal()
        try:
            enabled = get_settings(db).lock_connector_until_authorized
        finally:
            db.close()
        if not enabled:
            return
        await self._set_connector_lock(False)
        self._schedule_relock()

        # เครื่องบางรุ่นตัดสินใจตอน "แตะบัตร" ว่าจะเริ่มชาร์จเองหรือไม่ โดยเช็ค availability
        # ของตัวเองในจังหวะที่ยังเป็น Inoperative อยู่ (เพราะเราเพิ่งปลดล็อคหลัง Authorize.conf
        # ตอบกลับไปแล้ว) ทำให้มันปฏิเสธไม่เริ่มชาร์จทั้งที่บัตรผ่านแล้ว จึงต้องสั่ง
        # RemoteStartTransaction ซ้ำจากฝั่ง server เองหลังปลดล็อคเสร็จ แทนที่จะรอให้เครื่องเริ่มเอง
        try:
            response = await self.remote_start_transaction(id_tag, connector_id=1)
            logger.info(
                "[AutoLock] สั่ง RemoteStartTransaction ให้ %s หลังปลดล็อค: %s",
                self.id, getattr(response, "status", response),
            )
        except asyncio.TimeoutError:
            logger.warning("[AutoLock] %s ไม่ตอบสนองต่อ RemoteStartTransaction (timeout)", self.id)
        except Exception:
            logger.exception("[AutoLock] สั่ง RemoteStartTransaction ไปยัง %s ไม่สำเร็จ", self.id)

    @on(Action.start_transaction)
    async def on_start_transaction(self, connector_id, id_tag, meter_start, timestamp, **kwargs):
        last_tag = getattr(self, "_last_authorized_tag", None)
        last_at = getattr(self, "_last_authorized_at", None)
        authorized_recently = (
            last_tag == id_tag
            and last_at is not None
            and (datetime.utcnow() - last_at) <= timedelta(seconds=REAUTHORIZE_TIMEOUT_SECONDS)
        )
        if not authorized_recently:
            # เครื่องบางรุ่นจำ idTag ล่าสุดไว้ในตัวเครื่องแล้วเริ่มชาร์จเองตอนเสียบสาย โดยไม่ส่ง
            # Authorize มาถามเราใหม่เลย (ลอง ChangeConfiguration ปิด LocalPreAuthorize/
            # LocalAuthorizeOffline แล้วก็ไม่ช่วย เครื่องไม่ทำตามจริง) จึงต้องเช็คเองว่ามีการแตะบัตร/
            # กดเริ่มชาร์จผ่านมาจริงภายใน REAUTHORIZE_TIMEOUT_SECONDS ก่อนแล้วเท่านั้นถึงจะยอมรับ
            db = SessionLocal()
            try:
                logger.warning(
                    "StartTransaction %s: idTag=%s ไม่มีการแตะบัตร/เริ่มชาร์จผ่านมาก่อนภายใน %ss -> ปฏิเสธ (Blocked)",
                    self.id, id_tag, REAUTHORIZE_TIMEOUT_SECONDS,
                )
                log_event(
                    db, self.id, "StartTransaction",
                    {"connector_id": connector_id, "id_tag": id_tag, "meter_start": meter_start,
                     "rejected": "Blocked", "reason": "no_recent_authorization"},
                )
            finally:
                db.close()
            return call_result.StartTransaction(
                transaction_id=0,
                id_tag_info={"status": AuthorizationStatus.blocked},
            )

        db = SessionLocal()
        try:
            existing = (
                db.query(TransactionDB)
                .filter(
                    TransactionDB.charge_point_id == self.id,
                    TransactionDB.connector_id == connector_id,
                    TransactionDB.status == "Active",
                )
                .first()
            )
            if existing is not None:
                # เจอเครื่องบางรุ่นเข้า loop ส่ง StartTransaction ซ้ำๆ ทุกไม่กี่วินาทีโดยไม่เคย
                # StopTransaction ปิด session เดิมและไม่เคยจ่ายไฟจริง (bug ฝั่งเฟิร์มแวร์เครื่อง)
                # ปฏิเสธด้วย ConcurrentTx แทนการสร้าง transaction ซ้ำเพิ่มเรื่อยๆ ในระบบ
                logger.warning(
                    "StartTransaction %s: connector=%s มี transaction #%s ที่ยัง Active ค้างอยู่ -> ปฏิเสธ (ConcurrentTx)",
                    self.id, connector_id, existing.id,
                )
                log_event(
                    db, self.id, "StartTransaction",
                    {"connector_id": connector_id, "id_tag": id_tag, "meter_start": meter_start,
                     "rejected": "ConcurrentTx", "existing_transaction_id": existing.id},
                )
                return call_result.StartTransaction(
                    transaction_id=existing.id,
                    id_tag_info={"status": AuthorizationStatus.concurrent_tx},
                )

            # หา owner ของบัตรนี้ เพื่อกำหนดเพดานเงิน (budget) ของ session นี้: ถ้าตั้งงบ "รอบถัดไป"
            # ไว้ล่วงหน้า ใช้ค่านั้น (ใช้ครั้งเดียวแล้วเคลียร์) ไม่งั้นใช้ยอด wallet ทั้งหมดเป็นเพดาน
            # (โหมด "ปล่อยชาร์จจนเงินหมด")
            budget = None
            card = db.query(RFIDCardDB).filter(RFIDCardDB.card_uid == id_tag).first()
            owner = db.get(UserDB, card.user_id) if card and card.user_id else None
            if owner is not None:
                if owner.next_session_budget is not None:
                    budget = owner.next_session_budget
                    owner.next_session_budget = None
                else:
                    budget = owner.wallet_balance

            txn = TransactionDB(
                charge_point_id=self.id,
                connector_id=connector_id,
                id_tag=id_tag,
                meter_start=meter_start,
                start_time=datetime.utcnow(),
                status="Active",
                budget=budget,
            )
            db.add(txn)
            db.commit()
            db.refresh(txn)
            transaction_id = txn.id
            log_event(db, self.id, "StartTransaction", {"connector_id": connector_id, "id_tag": id_tag, "meter_start": meter_start, "budget": budget})
        finally:
            db.close()

        logger.info("StartTransaction %s: connector=%s txnId=%s", self.id, connector_id, transaction_id)
        # เริ่มชาร์จจริงแล้ว ไม่ต้องล็อคคืนอัตโนมัติจากตัวจับเวลาหลังแตะบัตรอีกต่อไป
        _cancel_relock_task(self.id)
        self._budget_stop_sent = False
        return call_result.StartTransaction(
            transaction_id=transaction_id,
            id_tag_info={"status": AuthorizationStatus.accepted},
        )

    @on(Action.stop_transaction)
    async def on_stop_transaction(self, meter_stop, timestamp, transaction_id, **kwargs):
        db = SessionLocal()
        try:
            txn = db.get(TransactionDB, transaction_id)
            if txn:
                txn.meter_stop = meter_stop
                txn.stop_time = datetime.utcnow()
                txn.status = "Completed"
                settings = get_settings(db)
                energy_kwh = max(0.0, (meter_stop - txn.meter_start) / 1000)
                txn.amount_due = round(energy_kwh * settings.price_per_kwh, 2)
                # เช็คงบระหว่างชาร์จ (on_meter_values) ทำได้แค่เป็นช่วงๆ ตามรอบที่เครื่องส่ง
                # MeterValues เข้ามา ไม่ใช่ real-time ต่อเนื่อง จึงมีโอกาสไฟไหลเกินงบไปเล็กน้อยก่อน
                # คำสั่งหยุดจะมีผลจริง (overshoot ทางกายภาพ ห้ามไม่ได้ 100%) — แต่ยืนยันได้แน่นอนว่า
                # "เงินที่หักจาก wallet ต้องไม่เกินงบที่ตั้งไว้" โดย clamp ยอดหักไว้ที่งบเสมอ
                # ส่วนต่างที่เกินมาถือเป็นต้นทุนที่ระบบออกให้ ไม่เรียกเก็บลูกค้าเพิ่ม
                if txn.budget is not None:
                    txn.amount_due = min(txn.amount_due, txn.budget)
                card = db.query(RFIDCardDB).filter(RFIDCardDB.card_uid == txn.id_tag).first()
                owner = db.get(UserDB, card.user_id) if card and card.user_id else None
                if owner is not None and txn.amount_due:
                    owner.wallet_balance -= txn.amount_due
                    db.add(WalletLedgerDB(
                        user_id=owner.id,
                        amount=-txn.amount_due,
                        reason="charge",
                        transaction_id=txn.id,
                        created_by="system",
                    ))
                db.commit()
            log_event(db, self.id, "StopTransaction", {"transaction_id": transaction_id, "meter_stop": meter_stop})
        finally:
            db.close()
        logger.info("StopTransaction %s: txnId=%s meterStop=%s", self.id, transaction_id, meter_stop)
        return call_result.StopTransaction(id_tag_info={"status": AuthorizationStatus.accepted})

    @after(Action.stop_transaction)
    async def after_stop_transaction(self, **kwargs):
        # จบ transaction แล้ว ล็อคเครื่องคืน (Inoperative) ถ้าเปิดโหมด "ล็อคจนกว่าจะแตะบัตร" ไว้
        # เพื่อให้คนถัดไปต้องแตะบัตรที่ลงทะเบียนก่อนถึงจะใช้เครื่องต่อได้
        db = SessionLocal()
        try:
            enabled = get_settings(db).lock_connector_until_authorized
        finally:
            db.close()
        if enabled:
            await self._set_connector_lock(True)

    @on(Action.meter_values)
    async def on_meter_values(self, connector_id, meter_value, **kwargs):
        db = SessionLocal()
        exceeded_txn_id = None
        try:
            transaction_id = kwargs.get("transaction_id")
            for mv in meter_value:
                for sampled in mv.get("sampled_value", []):
                    measurand = sampled.get("measurand", "Energy.Active.Import.Register")
                    value = float(sampled.get("value", 0) or 0)
                    entry = MeterValueDB(
                        charge_point_id=self.id,
                        transaction_id=transaction_id,
                        connector_id=connector_id,
                        measurand=measurand,
                        value=value,
                        unit=sampled.get("unit"),
                    )
                    db.add(entry)
                    if transaction_id and measurand == "Energy.Active.Import.Register":
                        txn = db.get(TransactionDB, transaction_id)
                        if txn and txn.status == "Active" and txn.budget is not None:
                            consumed_kwh = max(0.0, (value - txn.meter_start) / 1000)
                            cost_so_far = consumed_kwh * get_settings(db).price_per_kwh
                            if cost_so_far >= txn.budget:
                                exceeded_txn_id = transaction_id
            db.commit()
        finally:
            db.close()
        # เช็คงบ/ยอด wallet เกินแล้ว สั่งหยุดชาร์จอัตโนมัติ ต้องทำใน @after เท่านั้น (เหตุผลเดียวกับ
        # after_stop_transaction/after_authorize — ส่ง Call ใหม่ก่อนตอบ .conf เดิมจะ deadlock recv loop)
        if exceeded_txn_id is not None and not getattr(self, "_budget_stop_sent", False):
            self._budget_stop_sent = True
            self._budget_exceeded_transaction_id = exceeded_txn_id
        return call_result.MeterValues()

    @after(Action.meter_values)
    async def after_meter_values(self, **kwargs):
        txn_id = getattr(self, "_budget_exceeded_transaction_id", None)
        if txn_id is None:
            return
        self._budget_exceeded_transaction_id = None
        try:
            await self.remote_stop_transaction(txn_id)
        except (asyncio.TimeoutError, Exception) as exc:
            logger.warning(
                "[BudgetAutoStop] %s: สั่งหยุดชาร์จอัตโนมัติไม่สำเร็จ (txn=%s): %s", self.id, txn_id, exc
            )

    @on(Action.data_transfer)
    async def on_data_transfer(self, vendor_id, **kwargs):
        return call_result.DataTransfer(status="Accepted")

    # ---------- ล็อค/ปลดล็อคเครื่องอัตโนมัติ (โหมด "ล็อคจนกว่าจะแตะบัตร") ----------

    async def _set_connector_lock(self, locked: bool, connector_id: int = 1) -> None:
        target = AvailabilityType.inoperative if locked else AvailabilityType.operative
        try:
            response = await self.change_availability(connector_id, target)
        except asyncio.TimeoutError:
            logger.warning(
                "[AutoLock] %s ไม่ตอบสนองต่อคำสั่ง %s (timeout) connector=%s",
                self.id, target, connector_id,
            )
            return
        except Exception:
            logger.exception("[AutoLock] ส่งคำสั่ง %s ไปยัง %s ไม่สำเร็จ", target, self.id)
            return
        logger.info("[AutoLock] %s -> %s: %s", self.id, target, getattr(response, "status", response))

    def _schedule_relock(self) -> None:
        _cancel_relock_task(self.id)

        async def _relock_after_timeout():
            try:
                await asyncio.sleep(REAUTHORIZE_TIMEOUT_SECONDS)
            except asyncio.CancelledError:
                return
            logger.info(
                "[AutoLock] %s แตะบัตรผ่านแล้วแต่ไม่เริ่มชาร์จภายใน %ss -> ล็อคเครื่องคืน",
                self.id, REAUTHORIZE_TIMEOUT_SECONDS,
            )
            await self._set_connector_lock(True)

        _RELOCK_TASKS[self.id] = asyncio.ensure_future(_relock_after_timeout())

    # ---------- คำสั่งที่ Server ส่งไปหาเครื่องชาร์จได้ ----------

    async def remote_start_transaction(self, id_tag: str, connector_id: int = 1):
        self._last_authorized_tag = id_tag
        self._last_authorized_at = datetime.utcnow()
        request = call.RemoteStartTransaction(id_tag=id_tag, connector_id=connector_id)
        return await self.call(request)

    async def remote_stop_transaction(self, transaction_id: int):
        request = call.RemoteStopTransaction(transaction_id=transaction_id)
        return await self.call(request)

    async def unlock_connector(self, connector_id: int = 1):
        request = call.UnlockConnector(connector_id=connector_id)
        return await self.call(request)

    async def reset(self, reset_type: str = "Soft"):
        request = call.Reset(type=reset_type)
        return await self.call(request)

    async def change_availability(self, connector_id: int, availability_type: str):
        request = call.ChangeAvailability(connector_id=connector_id, type=availability_type)
        logger.info("[ChangeAvailability] ส่ง request ไปยัง %s (connector=%s, type=%s)", self.id, connector_id, availability_type)
        try:
            response = await self.call(request, suppress=False)
        except asyncio.TimeoutError:
            logger.warning(
                "[ChangeAvailability] %s ไม่ตอบกลับภายใน %ss (timeout)", self.id, self._response_timeout
            )
            raise
        logger.info("[ChangeAvailability] ได้รับ response จาก %s: %s", self.id, response)
        if response.status == AvailabilityStatus.accepted:
            # อัพเดท status ใน DB ทันทีแบบ optimistic เพราะเครื่องบางรุ่นไม่ส่ง StatusNotification
            # ตามมาหลังรับคำสั่งนี้ ถ้าเครื่องส่งจริงค่านี้จะถูกเขียนทับด้วยค่าจริงจาก on_status_notification อยู่ดี
            db = SessionLocal()
            try:
                if availability_type == AvailabilityType.inoperative:
                    _upsert_charge_point(db, self.id, status="Unavailable")
                else:
                    _upsert_charge_point(db, self.id, status="Available")
            finally:
                db.close()
        return response

    async def get_configuration(self, key: list[str] | None = None):
        request = call.GetConfiguration(key=key)
        logger.info("[GetConfiguration] ส่ง request ไปยัง %s (key=%s)", self.id, key)
        try:
            response = await self.call(request, suppress=False)
        except asyncio.TimeoutError:
            logger.warning(
                "[GetConfiguration] %s ไม่ตอบกลับภายใน %ss (timeout)", self.id, self._response_timeout
            )
            raise
        logger.info("[GetConfiguration] ได้รับ response จาก %s", self.id)
        return response

    async def change_configuration(self, key: str, value: str):
        request = call.ChangeConfiguration(key=key, value=value)
        logger.info("[ChangeConfiguration] ส่ง request ไปยัง %s (key=%s, value=%s)", self.id, key, value)
        try:
            response = await self.call(request, suppress=False)
        except asyncio.TimeoutError:
            logger.warning(
                "[ChangeConfiguration] %s ไม่ตอบกลับภายใน %ss (timeout)", self.id, self._response_timeout
            )
            raise
        logger.info("[ChangeConfiguration] ได้รับ response จาก %s: %s", self.id, response)
        return response
