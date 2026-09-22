"""
ระบบ Backup ฐานข้อมูล: export / restore / scheduled auto-backup
ใช้ sqlite3.Connection.backup() (stdlib) เพื่อ copy ข้อมูลแบบ consistent
แม้จะมี connection อื่นเขียนอยู่พร้อมกัน (เครื่องชาร์จส่ง StatusNotification/MeterValues ตลอดเวลา)
"""

import asyncio
import logging
import os
import sqlite3
from datetime import datetime
from pathlib import Path

from app.database import DATA_DIR, DB_FILE_PATH, engine

logger = logging.getLogger("ocpp-backup")

BACKUP_DIR = os.path.join(DATA_DIR, "backups")
os.makedirs(BACKUP_DIR, exist_ok=True)

BACKUP_INTERVAL_HOURS = float(os.environ.get("BACKUP_INTERVAL_HOURS", "24"))
BACKUP_RETENTION_COUNT = int(os.environ.get("BACKUP_RETENTION_COUNT", "7"))

REQUIRED_TABLES = {"charge_points", "transactions", "users", "settings"}


def _ro_uri(path: str) -> str:
    """แปลง path เป็น sqlite3 URI แบบ read-only (จัดการ space/backslash ให้ถูกต้องข้าม OS)"""
    return Path(path).resolve().as_uri() + "?mode=ro"


def create_backup(prefix: str = "scheduled") -> str:
    """สร้าง snapshot ของฐานข้อมูลแบบ consistent ผ่าน sqlite3 backup API คืน path ไฟล์ที่สร้าง"""
    filename = f"ocpp-{prefix}-{datetime.utcnow():%Y%m%d-%H%M%S}.db"
    dest_path = os.path.join(BACKUP_DIR, filename)
    src = sqlite3.connect(_ro_uri(DB_FILE_PATH), uri=True)
    dest = sqlite3.connect(dest_path)
    try:
        src.backup(dest)
    finally:
        src.close()
        dest.close()
    logger.info("สร้าง backup แล้ว: %s", filename)
    cleanup_old_backups()
    return dest_path


def list_backups() -> list[dict]:
    """รายการไฟล์ backup ใน BACKUP_DIR เรียงจากใหม่ไปเก่า"""
    entries = []
    for name in os.listdir(BACKUP_DIR):
        if not name.endswith(".db"):
            continue
        path = os.path.join(BACKUP_DIR, name)
        stat = os.stat(path)
        entries.append(
            {
                "filename": name,
                "size_bytes": stat.st_size,
                "created_at": datetime.utcfromtimestamp(stat.st_mtime).isoformat(),
            }
        )
    entries.sort(key=lambda e: e["created_at"], reverse=True)
    return entries


def cleanup_old_backups(retention: int | None = None) -> None:
    """เก็บไฟล์ backup ล่าสุดไว้ตามจำนวน retention ที่กำหนด ลบที่เหลือทิ้ง"""
    if retention is None:
        retention = BACKUP_RETENTION_COUNT
    for entry in list_backups()[retention:]:
        try:
            os.remove(os.path.join(BACKUP_DIR, entry["filename"]))
            logger.info("ลบ backup เก่าออก: %s", entry["filename"])
        except OSError:
            logger.exception("ลบไฟล์ backup ไม่สำเร็จ: %s", entry["filename"])


def validate_sqlite_file(path: str) -> None:
    """เช็คว่าไฟล์เป็น SQLite database ที่ใช้ได้จริงและมีตารางหลักครบ ไม่งั้น raise ValueError"""
    with open(path, "rb") as f:
        header = f.read(16)
    if header != b"SQLite format 3\x00":
        raise ValueError("ไฟล์ที่อัพโหลดไม่ใช่ไฟล์ SQLite database")

    conn = sqlite3.connect(_ro_uri(path), uri=True)
    try:
        (result,) = conn.execute("PRAGMA integrity_check").fetchone()
        if result != "ok":
            raise ValueError(f"ไฟล์ฐานข้อมูลเสียหาย: {result}")

        table_names = {
            row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")
        }
        missing = REQUIRED_TABLES - table_names
        if missing:
            raise ValueError(f"ไฟล์นี้ไม่ใช่ฐานข้อมูลของระบบนี้ (ไม่มีตาราง: {', '.join(sorted(missing))})")
    finally:
        conn.close()


def restore_from_file(uploaded_path: str) -> str:
    """Restore ฐานข้อมูลจากไฟล์ที่อัพโหลด: validate -> สำรองฐานข้อมูลปัจจุบันไว้ก่อน (กันพลาด)
    -> backup จากไฟล์ที่อัพโหลดเข้าไปทับฐานข้อมูลจริง -> reset connection pool
    คืน path ของไฟล์ safety-backup ที่สร้างไว้ก่อน restore"""
    validate_sqlite_file(uploaded_path)

    pre_restore_path = create_backup(prefix="pre-restore")

    src = sqlite3.connect(_ro_uri(uploaded_path), uri=True)
    dest = sqlite3.connect(DB_FILE_PATH)
    try:
        src.backup(dest)
    finally:
        src.close()
        dest.close()

    engine.dispose()
    logger.warning("Restore ฐานข้อมูลเรียบร้อย (safety backup: %s)", pre_restore_path)
    return pre_restore_path


async def scheduled_backup_loop() -> None:
    """Background task: สร้าง backup อัตโนมัติทุก BACKUP_INTERVAL_HOURS ชั่วโมง"""
    interval_seconds = BACKUP_INTERVAL_HOURS * 3600
    while True:
        await asyncio.sleep(interval_seconds)
        try:
            await asyncio.to_thread(create_backup, "scheduled")
        except Exception:
            logger.exception("Scheduled backup ล้มเหลว")
