"""
การตั้งค่าฐานข้อมูล (SQLite) และ Model ต่างๆ
ใช้ SQLite ไฟล์เดียวเก็บใน ./data/ocpp.db เพื่อให้ mount เป็น volume บน Coolify ได้ง่าย
"""

import datetime
import os

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    create_engine,
)
from sqlalchemy.orm import Session, declarative_base, sessionmaker

DATA_DIR = os.environ.get("DATA_DIR", "./data")
os.makedirs(DATA_DIR, exist_ok=True)

DB_FILE_PATH = os.path.join(DATA_DIR, "ocpp.db")
DATABASE_URL = f"sqlite:///{DB_FILE_PATH}"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)
Base = declarative_base()


class ChargePointDB(Base):
    __tablename__ = "charge_points"

    id = Column(String, primary_key=True)  # ChargePointID ที่ตั้งในตัวเครื่องชาร์จ
    vendor = Column(String, nullable=True)
    model = Column(String, nullable=True)
    firmware_version = Column(String, nullable=True)
    status = Column(String, default="Unknown")
    error_code = Column(String, nullable=True)
    connector_id = Column(Integer, default=1)
    is_online = Column(Boolean, default=False)
    last_heartbeat = Column(DateTime, nullable=True)
    last_seen = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class TransactionDB(Base):
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    charge_point_id = Column(String, ForeignKey("charge_points.id"))
    connector_id = Column(Integer)
    id_tag = Column(String)
    meter_start = Column(Float)
    meter_stop = Column(Float, nullable=True)
    start_time = Column(DateTime)
    stop_time = Column(DateTime, nullable=True)
    status = Column(String, default="Active")  # Active / Completed
    amount_due = Column(Float, nullable=True)  # ค่าใช้จ่ายของ session นี้ (บาท) หักจาก wallet ทันทีตอน StopTransaction
    budget = Column(Float, nullable=True)  # เพดานเงิน (บาท) ของ session นี้ (snapshot ตอนเริ่ม ใช้เช็ค auto-stop)


class MeterValueDB(Base):
    __tablename__ = "meter_values"

    id = Column(Integer, primary_key=True, autoincrement=True)
    charge_point_id = Column(String, ForeignKey("charge_points.id"))
    transaction_id = Column(Integer, nullable=True)
    connector_id = Column(Integer)
    timestamp = Column(DateTime, default=datetime.datetime.utcnow)
    measurand = Column(String, default="Energy.Active.Import.Register")
    value = Column(Float)
    unit = Column(String, nullable=True)


class EventLogDB(Base):
    """เก็บ log ทุก OCPP action ที่เข้ามา สำหรับ debug/ดูประวัติ"""

    __tablename__ = "event_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    charge_point_id = Column(String, index=True)
    action = Column(String)
    payload = Column(String)
    timestamp = Column(DateTime, default=datetime.datetime.utcnow)


class AdminUserDB(Base):
    """LEGACY: ระบบ Admin login แบบเก่า (ก่อนมีระบบ users/role) เก็บไว้เพื่ออ่านตอน migrate
    เข้า UserDB เท่านั้น ห้ามใช้งานที่อื่นอีก"""

    __tablename__ = "admin_users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String, unique=True, index=True)
    password_hash = Column(String)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class UserDB(Base):
    """ผู้ใช้งานระบบ: admin / staff / customer"""

    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    username = Column(String, unique=True, index=True)
    password_hash = Column(String)
    full_name = Column(String, nullable=True)
    email = Column(String, nullable=True)
    phone = Column(String, nullable=True)
    role = Column(String, default="customer")  # admin / staff / customer
    is_active = Column(Boolean, default=True)
    wallet_balance = Column(Float, default=0)  # ยอดเงินคงเหลือ (บาท) ในกระเป๋า prepaid
    next_session_budget = Column(Float, nullable=True)  # งบที่ตั้งไว้สำหรับรอบชาร์จถัดไป (ใช้ครั้งเดียวแล้วเคลียร์)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class RFIDCardDB(Base):
    """บัตร RFID ที่ผูกกับ user แต่ละคน (card_uid = OCPP idTag)"""

    __tablename__ = "rfid_cards"

    id = Column(Integer, primary_key=True, autoincrement=True)
    card_uid = Column(String, unique=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    is_active = Column(Boolean, default=True)
    balance = Column(Float, default=0)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class CardTapDB(Base):
    """Log การแตะบัตร RFID ทุกครั้งที่เครื่องชาร์จส่ง Authorize เข้ามา"""

    __tablename__ = "card_taps"

    id = Column(Integer, primary_key=True, autoincrement=True)
    charge_point_id = Column(String, index=True)
    card_uid = Column(String, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    status = Column(String)  # Accepted / Blocked / Invalid / Expired / ConcurrentTx
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class WalletLedgerDB(Base):
    """ประวัติการเติม/หักเงินกระเป๋าของ user แต่ละคน"""

    __tablename__ = "wallet_ledger"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True)
    amount = Column(Float)  # + = เติมเงิน, - = หักค่าชาร์จ
    reason = Column(String)  # "topup" / "charge"
    transaction_id = Column(Integer, nullable=True)  # ผูกกับ TransactionDB.id ถ้า reason == "charge"
    note = Column(String, nullable=True)
    created_by = Column(String, nullable=True)  # username admin ที่เติม, หรือ "system" ตอนหักอัตโนมัติ
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


class SettingsDB(Base):
    """ค่าตั้งค่าระบบ (แถวเดียว, id เป็น 1 เสมอ)"""

    __tablename__ = "settings"

    id = Column(Integer, primary_key=True, default=1)
    system_name = Column(String, default="OCPP 1.6J Central System")
    heartbeat_interval = Column(Integer, default=30)  # วินาที ส่งให้เครื่องชาร์จตอน BootNotification
    auto_accept_authorize = Column(Boolean, default=True)  # true = accept ทุกบัตร RFID, false = ปฏิเสธทั้งหมด
    lock_connector_until_authorized = Column(Boolean, default=False)
    # true = สั่งให้เครื่องชาร์จ Inoperative (ล็อค ไม่พร้อมใช้งาน) ทันทีที่ boot/จบ transaction
    # แล้วจะสั่ง Operative (ปลดล็อค) ให้อัตโนมัติเมื่อมีการแตะบัตรที่ authorize ผ่านเท่านั้น
    price_per_kwh = Column(Float, default=7.0)  # ราคาค่าไฟ (บาท) ต่อหน่วย ใช้เรทเดียวกันทุกหัวชาร์จ ใช้คำนวณหักเงินจาก wallet
    allow_customer_mock_topup = Column(Boolean, default=False)
    # true = ให้ลูกค้าเติมเงินเข้า wallet ของตัวเองได้ทันที (โหมดทดสอบ ยังไม่ผูก payment gateway จริง
    # เงินไม่ได้เคลื่อนไหวจริง) ใช้ปิดไว้เป็น default กันลูกค้าจริงเติมเงินปลอมใช้งานฟรี
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow)


class ChangelogDB(Base):
    """รายการ Change Log ของระบบ แก้ไขได้จากหน้า Admin"""

    __tablename__ = "changelog"

    id = Column(Integer, primary_key=True, autoincrement=True)
    version = Column(String)
    description = Column(String)
    created_at = Column(DateTime, default=datetime.datetime.utcnow)


def _migrate_add_missing_columns() -> None:
    """SQLite: Base.metadata.create_all() ไม่เพิ่ม column ใหม่ให้ตารางที่มีอยู่แล้ว
    จึงต้องเช็คและ ALTER TABLE ADD COLUMN เองสำหรับ column ที่เพิ่มเข้ามาทีหลัง"""
    with engine.connect() as conn:
        existing_settings = {row[1] for row in conn.exec_driver_sql("PRAGMA table_info(settings)")}
        settings_columns = [
            ("lock_connector_until_authorized", "BOOLEAN DEFAULT 0"),
            ("price_per_kwh", "FLOAT DEFAULT 7.0"),
            ("allow_customer_mock_topup", "BOOLEAN DEFAULT 0"),
        ]
        for col, ddl in settings_columns:
            if col not in existing_settings:
                conn.exec_driver_sql(f"ALTER TABLE settings ADD COLUMN {col} {ddl}")
                conn.commit()

        existing_txn = {row[1] for row in conn.exec_driver_sql("PRAGMA table_info(transactions)")}
        transaction_columns = [
            ("amount_due", "FLOAT"),
            ("budget", "FLOAT"),
        ]
        for col, ddl in transaction_columns:
            if col not in existing_txn:
                conn.exec_driver_sql(f"ALTER TABLE transactions ADD COLUMN {col} {ddl}")
                conn.commit()

        existing_users = {row[1] for row in conn.exec_driver_sql("PRAGMA table_info(users)")}
        user_columns = [
            ("wallet_balance", "FLOAT DEFAULT 0"),
            ("next_session_budget", "FLOAT"),
        ]
        for col, ddl in user_columns:
            if col not in existing_users:
                conn.exec_driver_sql(f"ALTER TABLE users ADD COLUMN {col} {ddl}")
                conn.commit()


def init_db() -> None:
    Base.metadata.create_all(bind=engine)
    _migrate_add_missing_columns()


def resolve_card_authorization(db: Session, id_tag: str) -> tuple[str, "RFIDCardDB | None"]:
    """เช็คว่า idTag/บัตรนี้อนุญาตให้ใช้งานหรือไม่ ใช้กติกาเดียวกันทั้งตอนเครื่องส่ง Authorize
    เข้ามาเอง และตอน admin/staff กด Remote Start จากหน้าเว็บ (ใส่ idTag เอง) เพื่อไม่ให้ผลลัพธ์
    ขัดแย้งกันระหว่างสองทาง คืนค่า (status, card) โดย status เป็น "Accepted" หรือ "Blocked"
    บัตรที่ไม่ผูก user หรือ user ที่ยอดเงินใน wallet หมด/ติดลบ จะถูก Block เสมอ (ระบบ prepaid)"""
    card = db.query(RFIDCardDB).filter(RFIDCardDB.card_uid == id_tag).first()
    if card is not None:
        if not card.is_active:
            return "Blocked", card
        owner = db.get(UserDB, card.user_id) if card.user_id else None
        if owner is None or owner.wallet_balance <= 0:
            return "Blocked", card
        return "Accepted", card
    status = "Accepted" if get_settings(db).auto_accept_authorize else "Blocked"
    return status, None


def get_settings(db: Session) -> SettingsDB:
    """คืนแถวการตั้งค่า (สร้างค่า default ถ้ายังไม่มี)"""
    settings = db.get(SettingsDB, 1)
    if settings is None:
        settings = SettingsDB(id=1)
        db.add(settings)
        db.commit()
        db.refresh(settings)
    return settings


def migrate_legacy_admin_users(db: Session) -> None:
    """ย้ายบัญชีจากระบบ Admin เก่า (admin_users) เข้า users ครั้งเดียว
    (password_hash เดิมเป็น pbkdf2 ยังใช้ได้ผ่าน legacy fallback ใน app/auth.py
    แล้วจะถูก re-hash เป็น bcrypt อัตโนมัติตอน login สำเร็จครั้งแรก)"""
    if db.query(UserDB).count() > 0:
        return

    legacy_admins = db.query(AdminUserDB).all()
    if not legacy_admins:
        return

    for legacy in legacy_admins:
        db.add(
            UserDB(
                username=legacy.username,
                password_hash=legacy.password_hash,
                role="admin",
                is_active=True,
            )
        )
    db.commit()


CHANGELOG_SEED = [
    ("v1.0", "เริ่มต้นระบบ OCPP 1.6J Central System"),
    (
        "v1.1",
        "เพิ่ม Admin panel, JWT auth พร้อมระบบ role, จัดการบัตร RFID, "
        "และปรับ UI ให้รองรับหน้าจอมือถือ",
    ),
    (
        "v1.2",
        "บังคับต้องแตะบัตร RFID ที่ลงทะเบียนแล้วก่อนถึงจะเริ่มชาร์จได้ (server ตรวจสอบเองไม่พึ่งเครื่อง), "
        "แสดงข้อมูลการชาร์จแบบ real-time (พลังงาน, เวลา, Voltage, Current, Power, Temperature) "
        "ทั้งในตาราง Dashboard และหน้ารายละเอียด, เพิ่มประวัติการแตะบัตร, แก้บั๊กการบันทึกค่ามิเตอร์ไฟฟ้า, "
        "เพิ่มคอลัมน์ระยะเวลาการชาร์จ, แก้ไขข้อมูลบัตร RFID ได้, "
        "และเพิ่มปุ่ม Reboot (Hard Reset) และปลดล็อคหัวชาร์จให้ใช้งานง่ายขึ้น",
    ),
]


def seed_defaults() -> None:
    """สร้างค่า default ตอนแอปเริ่มทำงานครั้งแรก: admin user, settings, changelog"""
    import logging

    from app.auth import hash_password

    logger = logging.getLogger("ocpp-server")
    db = SessionLocal()
    try:
        get_settings(db)

        migrate_legacy_admin_users(db)

        if db.query(UserDB).count() == 0:
            default_username = os.environ.get("ADMIN_USERNAME", "admin")
            default_password = os.environ.get("ADMIN_PASSWORD", "admin123")
            db.add(
                UserDB(
                    username=default_username,
                    password_hash=hash_password(default_password),
                    role="admin",
                    is_active=True,
                )
            )
            db.commit()
            logger.warning(
                "สร้างบัญชี Admin เริ่มต้น username=%s password=%s "
                "กรุณาเปลี่ยนรหัสผ่านทันทีหลังเข้าสู่ระบบครั้งแรก!",
                default_username,
                default_password,
            )

        existing_versions = {row[0] for row in db.query(ChangelogDB.version).all()}
        for version, description in CHANGELOG_SEED:
            if version not in existing_versions:
                db.add(ChangelogDB(version=version, description=description))
        db.commit()
    finally:
        db.close()


def get_db() -> Session:
    db = SessionLocal()
    try:
        return db
    finally:
        pass
