"""
ระบบ Auth: JWT (stateless) + bcrypt สำหรับ hash รหัสผ่าน
รองรับ verify รหัสผ่านแบบ pbkdf2 เก่า (จากระบบ Admin login เดิม) เป็น fallback
แล้ว re-hash เป็น bcrypt อัตโนมัติเมื่อ login สำเร็จครั้งแรก
"""

import hashlib
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

import jwt
from passlib.context import CryptContext

logger = logging.getLogger("ocpp-server")

ACCESS_TOKEN_COOKIE_NAME = "access_token"
ACCESS_TOKEN_EXPIRE_DAYS = 7

ENVIRONMENT = os.environ.get("ENVIRONMENT", "development")
JWT_SECRET = os.environ.get("JWT_SECRET")

if not JWT_SECRET:
    if ENVIRONMENT == "production":
        raise RuntimeError(
            "ต้องตั้งค่า environment variable JWT_SECRET ก่อน deploy production "
            "(เช่นใน Coolify -> Configuration -> Environment Variables)"
        )
    JWT_SECRET = "dev-only-insecure-secret-change-me"
    logger.warning(
        "ไม่ได้ตั้งค่า JWT_SECRET ใช้ค่า default สำหรับ dev เท่านั้น "
        "ห้ามใช้ค่านี้ใน production!"
    )

JWT_ALGORITHM = "HS256"

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def _legacy_pbkdf2_verify(password: str, stored_hash: str) -> bool:
    """ระบบ Admin login เดิม (ก่อนมี users/role) ใช้ pbkdf2 รูปแบบ salt$hex"""
    try:
        salt, digest_hex = stored_hash.split("$")
    except ValueError:
        return False
    import hmac

    digest = hashlib.pbkdf2_hmac("sha256", password.encode(), bytes.fromhex(salt), 100_000)
    return hmac.compare_digest(digest.hex(), digest_hex)


def verify_password(password: str, stored_hash: str) -> bool:
    if stored_hash.startswith("$2"):  # bcrypt hash
        return pwd_context.verify(password, stored_hash)
    return _legacy_pbkdf2_verify(password, stored_hash)


def is_legacy_hash(stored_hash: str) -> bool:
    return not stored_hash.startswith("$2")


def create_access_token(user_id: int, username: str, role: str) -> str:
    expire = datetime.now(timezone.utc) + timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS)
    payload = {"sub": str(user_id), "username": username, "role": role, "exp": expire}
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def decode_access_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
    except jwt.PyJWTError:
        return None
