"""
Database layer — เชื่อมต่อและสร้างโครงสร้างตาราง SQLite ด้วย `sqlite3` ล้วนๆ

Schema นี้ยึดตามเอกสารโครงงาน (ตาราง User, Menu Favorite, Menu ใน ER-Diagram
บทที่ 3) และตาราง Review (จาก Data Store D4) บวก constraint ที่ยืนยันร่วมกัน
ระหว่างการออกแบบ (อ้างอิงคำถาม A-D):

    A) Menu_Favorite: UNIQUE(UID, MID) — 1 คนกดถูกใจเมนูเดิมนับครั้งเดียว
    B) Review:        UNIQUE(UID, MID) — 1 คนรีวิวเมนูเดิมได้ 1 รายการ (แก้ไขแทนสร้างใหม่)
    C) Menu.Menu_name: ไม่ใส่ UNIQUE — เอกสารระบุแค่ Not null เท่านั้น
                       (การกันเมนูซ้ำตอน sync จาก KNN ทำที่ logic โปรแกรม
                       ใน menu_repository.py แทน ไม่ใช่ระดับ constraint)
    D) Review.Comment: Nullable — ให้คะแนนดาวอย่างเดียวได้โดยไม่ต้องคอมเมนต์

**ยังไม่แตะ:** auth.py (STEP 4/5), menu_repository.py ส่วน favorite/review
(รอคำสั่งว่าจะทำตอนนี้หรือ step หลัง — ดูท้ายรายงาน)
"""
from __future__ import annotations

import os
import sqlite3
from contextlib import contextmanager
from typing import Iterator

DB_PATH = os.environ.get("RECIPE_DB_PATH", "recipe_app.db")


_SCHEMA = """
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS User (
    UID            INTEGER PRIMARY KEY AUTOINCREMENT,
    Email          VARCHAR(50)  NOT NULL UNIQUE,
    Fullname       VARCHAR(50)  NOT NULL,
    Password       VARCHAR(100) NOT NULL,
    Tel            VARCHAR(10),
    Confirm_status INTEGER      NOT NULL DEFAULT 1 CHECK (Confirm_status IN (0, 1)),
    role           INTEGER      NOT NULL DEFAULT 1 CHECK (role IN (0, 1))
);

CREATE TABLE IF NOT EXISTS Menu (
    MID        INTEGER PRIMARY KEY AUTOINCREMENT,
    Menu_name  VARCHAR(20) NOT NULL,
    Image      VARCHAR(200),
    ingredient TEXT NOT NULL,
    method     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS Menu_Favorite (
    FID           INTEGER PRIMARY KEY AUTOINCREMENT,
    Favorite_Date DATE    NOT NULL DEFAULT (date('now')),
    UID           INTEGER NOT NULL,
    MID           INTEGER NOT NULL,
    FOREIGN KEY (UID) REFERENCES User (UID) ON DELETE CASCADE,
    FOREIGN KEY (MID) REFERENCES Menu (MID) ON DELETE CASCADE,
    UNIQUE (UID, MID)
);

CREATE TABLE IF NOT EXISTS Review (
    RID         INTEGER PRIMARY KEY AUTOINCREMENT,
    UID         INTEGER NOT NULL,
    MID         INTEGER NOT NULL,
    Score       INTEGER NOT NULL CHECK (Score BETWEEN 1 AND 5),
    Comment     TEXT,
    Review_Date DATE    NOT NULL DEFAULT (date('now')),
    FOREIGN KEY (UID) REFERENCES User (UID) ON DELETE CASCADE,
    FOREIGN KEY (MID) REFERENCES Menu (MID) ON DELETE CASCADE,
    UNIQUE (UID, MID)
);

CREATE INDEX IF NOT EXISTS idx_menu_favorite_uid ON Menu_Favorite (UID);
CREATE INDEX IF NOT EXISTS idx_review_mid ON Review (MID);
"""


def get_connection(db_path: str = DB_PATH) -> sqlite3.Connection:
    """เปิด connection ใหม่ — row_factory คืนผลแบบเข้าถึงด้วยชื่อคอลัมน์ได้
    (sqlite3.Row) และเปิด foreign key constraint (SQLite ปิดไว้เป็นค่าเริ่มต้น
    ต้องเปิดเองทุก connection ไม่งั้น FOREIGN KEY ... ON DELETE CASCADE ที่
    ประกาศไว้ใน schema จะไม่ทำงานจริง)
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON;")
    return conn


@contextmanager
def db_session(db_path: str = DB_PATH) -> Iterator[sqlite3.Connection]:
    """Context manager: เปิด connection, commit ถ้าไม่มี exception, rollback ถ้ามี, ปิดเสมอ"""
    conn = get_connection(db_path)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def init_db(db_path: str = DB_PATH) -> None:
    """สร้างตารางทั้งหมดถ้ายังไม่มี (เรียกซ้ำได้ปลอดภัย ไม่ลบข้อมูลเดิม) —
    เรียกอัตโนมัติตอน backend เริ่มทำงาน (ผูกไว้ที่ `service.get_engine()`)
    """
    with db_session(db_path) as conn:
        conn.executescript(_SCHEMA)
