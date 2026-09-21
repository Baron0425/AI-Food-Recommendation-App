"""
Authentication — STEP 4 (สมัครสมาชิก) + STEP 5 (ล็อกอิน + JWT)

**เรื่องรหัสผ่าน:** hash ด้วย `hashlib.pbkdf2_hmac` (standard library) + salt
สุ่มใหม่ทุกครั้งด้วย `secrets.token_hex` เก็บเป็น "salt$hash" ในคอลัมน์
`Password` เดียว — ไม่มีการเก็บ plain text ตามที่กำหนดไว้ (STEP 4 ข้อห้าม)

**เรื่อง JWT — แจ้ง dependency ใหม่ที่ต้องติดตั้งเพิ่ม:**
    Package: `PyJWT`
    เหตุผล: คุณเลือกใช้ JWT สำหรับ session (คำถามที่ 3) — Python standard
    library ไม่มีฟังก์ชัน encode/decode JWT ในตัว ต้องใช้ไลบรารีนอก และ
    `PyJWT` เป็นไลบรารีมาตรฐานที่นิยมใช้กับ FastAPI มากที่สุด (เบา ไม่มี
    dependency ซ้อนเยอะ) — เพิ่มไว้ใน requirements.txt แล้ว
    ติดตั้งด้วย: `pip install pyjwt`

Payload ของ JWT อ้างอิง UID และ role ตามที่ยืนยันไว้ (คำถามที่ 3) — ไม่มีการ
เพิ่มฟิลด์ JWT/session ลงในตาราง User ตามที่สั่งไว้ (เป็น stateless เก็บอยู่
ในตัว token เท่านั้น ฝั่ง DB ไม่ต้องรู้จัก token เลย)

**STEP 6 — Google OAuth — แจ้ง dependency ใหม่ที่ต้องติดตั้งเพิ่ม:**
    Package: `google-auth`
    เหตุผล: ใช้ตรวจสอบว่า ID Token ที่ Flutter ส่งมาเป็นของจริงจาก Google
    (เช็ก signature กับ public key ของ Google) — Python standard library ไม่มี
    ฟังก์ชันนี้ในตัว
    ติดตั้งด้วย: `pip install google-auth`

**เรื่อง Password ของ user ที่สมัครผ่าน Google เท่านั้น (ไม่เคยตั้งรหัสผ่านเอง):**
คอลัมน์ `Password` ในตาราง `User` เป็น `Not null` ตามเอกสาร แต่ผู้ใช้ที่เข้า
ระบบด้วย Google อย่างเดียวไม่เคยตั้งรหัสผ่านกับเราเลย จึงสุ่มค่าที่คาดเดา
ไม่ได้ (`secrets.token_urlsafe`) มา hash เก็บไว้แทน — **ไม่ใช่รหัสผ่านของ
Google** (ไม่ได้เก็บรหัสผ่าน Google ตามข้อห้ามในเอกสาร) เป็นแค่ค่าเติมคอลัมน์
ให้ไม่ null เฉยๆ ผู้ใช้จะ login ด้วยอีเมล+รหัสผ่านแบบปกติไม่ได้ (เพราะไม่มี
ทางรู้ค่าที่สุ่มมา) ต้อง login ผ่าน Google เท่านั้นจนกว่าจะตั้งรหัสผ่านเองใน
หน้าแก้ไขข้อมูลส่วนตัว (STEP 7)
"""
from __future__ import annotations

import hashlib
import os
import secrets
import sqlite3
import time
from dataclasses import dataclass

import jwt
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from database import db_session

_PBKDF2_ITERATIONS = 200_000
_SALT_BYTES = 16

# ตั้งผ่าน environment variable ได้ — ค่าเริ่มต้นนี้ใช้ได้เฉพาะตอน dev เท่านั้น
# ***ก่อนขึ้น production ต้องตั้ง RECIPE_JWT_SECRET เป็นค่าลับที่สุ่มเองแทน***
_JWT_SECRET = os.environ.get("RECIPE_JWT_SECRET", "dev-only-secret-change-me")
_JWT_ALGORITHM = "HS256"
_JWT_EXPIRE_SECONDS = int(os.environ.get("RECIPE_JWT_EXPIRE_SECONDS", str(7 * 24 * 3600)))  # 7 วัน

# ต้องไปสร้างที่ Google Cloud Console -> APIs & Services -> Credentials ->
# OAuth 2.0 Client ID (เลือกประเภท Android/iOS ตามแอพ) แล้วเอา Client ID
# (ลงท้ายด้วย .apps.googleusercontent.com) มาตั้งเป็น env var นี้ — ใช้ตรวจว่า
# token ที่ Flutter ส่งมาถูกออกให้แอพเราจริง ไม่ใช่แอพอื่น
_GOOGLE_CLIENT_ID = os.environ.get("RECIPE_GOOGLE_CLIENT_ID", "")


class AuthError(Exception):
    """เกิดจากการสมัคร/ล็อกอิน/token ไม่ถูกต้อง — message เอาไปโชว์ผู้ใช้ได้ตรงๆ"""


@dataclass
class User:
    uid: int
    email: str
    fullname: str
    tel: str | None
    confirm_status: int
    role: int  # 0 = admin, 1 = member (ตามเอกสาร)

    @property
    def is_admin(self) -> bool:
        return self.role == 0


# ---------------------------------------------------------------------------
# Password hashing
# ---------------------------------------------------------------------------


def hash_password(password: str) -> str:
    salt = secrets.token_hex(_SALT_BYTES)
    digest = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), _PBKDF2_ITERATIONS
    ).hex()
    return f"{salt}${digest}"


def verify_password(password: str, stored_hash: str) -> bool:
    try:
        salt, digest = stored_hash.split("$", 1)
    except ValueError:
        return False
    candidate = hashlib.pbkdf2_hmac(
        "sha256", password.encode("utf-8"), salt.encode("utf-8"), _PBKDF2_ITERATIONS
    ).hex()
    return secrets.compare_digest(candidate, digest)  # กัน timing attack


def _row_to_user(row: sqlite3.Row) -> User:
    return User(
        uid=row["UID"],
        email=row["Email"],
        fullname=row["Fullname"],
        tel=row["Tel"],
        confirm_status=row["Confirm_status"],
        role=row["role"],
    )


# ---------------------------------------------------------------------------
# STEP 4 — สมัครสมาชิก
# ---------------------------------------------------------------------------


def register_user(
    email: str,
    fullname: str,
    password: str,
    tel: str | None = None,
) -> User:
    """สมัครสมาชิกใหม่ ตามขั้นตอนที่ระบุใน STEP 4:
        1. ตรวจสอบ Email ซ้ำ (ผ่าน UNIQUE constraint ของ DB — ดักเป็น AuthError)
        2. Hash Password ก่อนบันทึก
        3. UID สร้างอัตโนมัติจาก AUTOINCREMENT
        4. role = 1 (member) เสมอ — ค่า default ของคอลัมน์ใน DB อยู่แล้ว
        5. Confirm_status = 1 เสมอ (ยืนยันไว้ในคำถามที่ 2 — ไม่มีระบบยืนยัน
           อีเมล/OTP จึงตั้งให้ใช้งานได้ทันทีหลังสมัคร)
        6. บันทึกลง SQLite
    """
    email = email.strip().lower()
    fullname = fullname.strip()

    if not email or not fullname or not password:
        raise AuthError("กรุณากรอกอีเมล ชื่อ-นามสกุล และรหัสผ่านให้ครบ")
    if "@" not in email:
        raise AuthError("รูปแบบอีเมลไม่ถูกต้อง")
    if len(password) < 8:
        raise AuthError("รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร")

    password_hash = hash_password(password)

    try:
        with db_session() as conn:
            cursor = conn.execute(
                """
                INSERT INTO User (Email, Fullname, Password, Tel, Confirm_status, role)
                VALUES (?, ?, ?, ?, 1, 1)
                """,
                (email, fullname, password_hash, tel),
            )
            uid = cursor.lastrowid
    except sqlite3.IntegrityError as exc:
        raise AuthError("อีเมลนี้มีคนใช้แล้ว") from exc

    return get_user_by_id(uid)  # type: ignore[return-value]


# ---------------------------------------------------------------------------
# STEP 5 — Login
# ---------------------------------------------------------------------------


def authenticate(email: str, password: str) -> User:
    """ตรวจอีเมล+รหัสผ่านตามขั้นตอนที่ระบุใน STEP 5:
        1-2. รับ Email/Password แล้วค้นหา User จาก Email
        3. ตรวจสอบ Password กับ Password Hash
        4. ตรวจสอบสถานะบัญชี (Confirm_status)
        5. role จะถูกใส่ใน JWT ต่อ (ดู create_access_token) เพื่อให้ตรวจสิทธิ์
           Admin/Member ได้ตอนเรียก API อื่นๆ ทีหลัง

    ใช้ข้อความ error เดียวกันทั้งกรณี "ไม่มีอีเมลนี้" และ "รหัสผ่านผิด" กัน
    user enumeration
    """
    email = email.strip().lower()

    with db_session() as conn:
        row = conn.execute("SELECT * FROM User WHERE Email = ?", (email,)).fetchone()

    if row is None or not verify_password(password, row["Password"]):
        raise AuthError("อีเมลหรือรหัสผ่านไม่ถูกต้อง")

    if row["Confirm_status"] != 1:
        raise AuthError("บัญชีนี้ยังไม่ได้ยืนยัน กรุณาติดต่อผู้ดูแลระบบ")

    return _row_to_user(row)


def authenticate_google(google_id_token_str: str) -> User:
    """STEP 6 — ล็อกอิน/สมัครสมาชิกผ่าน Google OAuth

    ขั้นตอนตามที่กำหนดไว้:
        1. ตรวจสอบ ID Token กับ Google ก่อน (signature + audience ตรงกับแอพเรา)
        2. เอาอีเมลที่ตรวจสอบแล้วไปเทียบกับ User ใน SQLite
        3. ถ้ามีอีเมลนี้อยู่แล้ว -> เชื่อมเข้ากับ User เดิม (ไม่แตะ role เดิม
           ไม่ว่าจะเป็นอะไรอยู่ก่อน — กันไม่ให้ Google Login เปลี่ยน role)
        4. ถ้ายังไม่มี -> สร้าง User ใหม่ role=1 (member) เสมอ, ไม่เก็บรหัสผ่าน
           Google ใดๆ (ดูคำอธิบาย placeholder password ด้านบนของไฟล์)

    ป้องกัน user ซ้ำจาก Email เดียวกัน เพราะเช็ก Email ก่อนสร้างเสมอ (ไม่ใช่
    สร้างใหม่ทุกครั้งที่ login ผ่าน Google)
    """
    if not _GOOGLE_CLIENT_ID:
        raise AuthError(
            "เซิร์ฟเวอร์ยังไม่ได้ตั้งค่า RECIPE_GOOGLE_CLIENT_ID — "
            "ติดต่อผู้ดูแลระบบ"
        )

    try:
        payload = google_id_token.verify_oauth2_token(
            google_id_token_str,
            google_requests.Request(),
            _GOOGLE_CLIENT_ID,
        )
    except ValueError as exc:
        # token ปลอม/หมดอายุ/audience ไม่ตรง — google-auth โยน ValueError รวมๆ
        raise AuthError("Google ID Token ไม่ถูกต้องหรือหมดอายุ") from exc

    email = payload.get("email")
    if not email:
        raise AuthError("บัญชี Google นี้ไม่มีอีเมล ไม่สามารถล็อกอินได้")
    if not payload.get("email_verified", False):
        raise AuthError("อีเมล Google นี้ยังไม่ได้ยืนยันกับ Google")

    email = email.strip().lower()
    existing = get_user_by_email(email)
    if existing is not None:
        # เชื่อมกับ user เดิม — ไม่แก้ role/ข้อมูลอื่นใดๆ ของ user เดิมเลย
        return existing

    fullname = payload.get("name") or email.split("@", 1)[0]
    # รหัสผ่านสุ่มที่ไม่มีใครรู้ (รวมถึงตัวผู้ใช้เอง) — ไม่ใช่รหัสผ่าน Google
    # แค่เติมคอลัมน์ Password (Not null) ให้ครบ ผู้ใช้จะ login ด้วย
    # อีเมล+รหัสผ่านแบบปกติไม่ได้จนกว่าจะไปตั้งรหัสผ่านเองภายหลัง
    random_password_hash = hash_password(secrets.token_urlsafe(32))

    with db_session() as conn:
        cursor = conn.execute(
            """
            INSERT INTO User (Email, Fullname, Password, Tel, Confirm_status, role)
            VALUES (?, ?, ?, NULL, 1, 1)
            """,
            (email, fullname, random_password_hash),
        )
        uid = cursor.lastrowid

    return get_user_by_id(uid)  # type: ignore[return-value]


def get_user_by_id(uid: int) -> User | None:
    with db_session() as conn:
        row = conn.execute("SELECT * FROM User WHERE UID = ?", (uid,)).fetchone()
    return _row_to_user(row) if row else None


def get_user_by_email(email: str) -> User | None:
    with db_session() as conn:
        row = conn.execute(
            "SELECT * FROM User WHERE Email = ?", (email.strip().lower(),)
        ).fetchone()
    return _row_to_user(row) if row else None


# ---------------------------------------------------------------------------
# JWT — ออก/ตรวจ token (คำถามที่ 3: stateless, payload อ้างอิง UID + role)
# ---------------------------------------------------------------------------


def create_access_token(user: User) -> str:
    now = int(time.time())
    payload = {
        "UID": user.uid,
        "role": user.role,
        "iat": now,
        "exp": now + _JWT_EXPIRE_SECONDS,
    }
    return jwt.encode(payload, _JWT_SECRET, algorithm=_JWT_ALGORITHM)


def decode_access_token(token: str) -> dict:
    """ถอดรหัส JWT — คืน payload (dict มี UID, role) ถ้า token ถูกต้องและยังไม่หมดอายุ
    โยน AuthError ถ้า token ผิด/หมดอายุ/ถูกแก้ไข
    """
    try:
        return jwt.decode(token, _JWT_SECRET, algorithms=[_JWT_ALGORITHM])
    except jwt.ExpiredSignatureError as exc:
        raise AuthError("Token หมดอายุ กรุณาเข้าสู่ระบบใหม่") from exc
    except jwt.InvalidTokenError as exc:
        raise AuthError("Token ไม่ถูกต้อง") from exc


def get_current_user(token: str) -> User:
    """แปลง JWT -> User object เต็ม (ดึงข้อมูลล่าสุดจาก DB ด้วย UID ใน token
    แทนที่จะเชื่อข้อมูลใน token เฉยๆ เผื่อ role/สถานะบัญชีถูกเปลี่ยนหลังออก
    token ไปแล้ว — เช่นแอดมินลด role คนอื่น ระหว่างที่ token เก่ายังไม่หมดอายุ)
    """
    payload = decode_access_token(token)
    user = get_user_by_id(payload["UID"])
    if user is None:
        raise AuthError("ไม่พบผู้ใช้นี้ในระบบ (บัญชีอาจถูกลบไปแล้ว)")
    return user
