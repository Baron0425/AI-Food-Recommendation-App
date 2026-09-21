"""
Repository สำหรับตาราง Menu / Menu_Favorite / Review (ตาม schema ใน database.py)

**แก้ไขจากไฟล์เดิม:** ไฟล์เดิมอ้างอิงตาราง/คอลัมน์ของ schema เก่า (`menu`,
`name`, `ingredients` (JSON), `menu_favorite`, `user_id`, `rating`) ซึ่งไม่มี
อยู่แล้วหลัง STEP 3 เปลี่ยน schema เขียนใหม่ทั้งไฟล์ให้ตรงกับ `Menu` (MID,
Menu_name, Image, ingredient, method), `Menu_Favorite` (FID, Favorite_Date,
UID, MID), `Review` (RID, UID, MID, Score, Comment, Review_Date)

**จุดที่ตัดสินใจเอง (เรื่องเล็ก ไม่ใช่โครงสร้าง DB จึงไม่หยุดถาม):**
    - คอลัมน์ `ingredient` ในเอกสารเป็น type `text` และตัวอย่างข้อมูลเป็น
      ข้อความอ่านง่ายแบบมีเลขข้อ ("1. น่องไก่/สะโพกไก่/อกไก่ ... 2. ...")
      ไม่ใช่ JSON array จึงเปลี่ยนจากเดิมที่เก็บเป็น JSON string มาเป็น
      "join ด้วยขึ้นบรรทัดใหม่" แทน ให้ตรงกับลักษณะ "text" ที่เอกสารตั้งใจ
    - `Image` ปล่อยเป็น NULL ตอน sync จากโมเดล KNN เพราะ `full_data` ไม่มี
      ข้อมูลรูปภาพให้ (ยังไม่ได้ทำฟีเจอร์อัปโหลดรูป) — คอลัมน์นี้ Nullable
      อยู่แล้วตามเอกสาร ไม่ผิด constraint ใดๆ
"""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from typing import Any

from database import db_session


@dataclass
class MenuRow:
    mid: int
    menu_name: str
    image: str | None
    ingredient: str
    method: str
    # ใส่ค่าจริงเฉพาะตอนมาจาก list_popular_menus() (ต้องคำนวณเพิ่ม) — ฟังก์ชัน
    # อื่น (get_menu_by_id, list_favorites ฯลฯ) ไม่ query คอลัมน์นี้ จึงปล่อย
    # เป็นค่า default ไว้ ไม่ error แม้ไม่ได้ตั้งใจใช้งานตรงนั้น
    average_score: float | None = None
    review_count: int = 0


def _row_to_menu(row: sqlite3.Row) -> MenuRow:
    return MenuRow(
        mid=row["MID"],
        menu_name=row["Menu_name"],
        image=row["Image"],
        ingredient=row["ingredient"],
        method=row["method"],
    )


# ---------------------------------------------------------------------------
# Menu — ข้อมูลหลักของเมนู (sync มาจาก full_data ที่ data_loader.py โหลดไว้)
# ---------------------------------------------------------------------------


def sync_menus_from_engine(full_data: list[dict[str, Any]]) -> int:
    """เอาข้อมูลเมนูจาก `full_data` (โครงสร้างเดียวกับที่ `data_loader.load_data()`
    คืนมา) ไป insert ลงตาราง `Menu`

    เอกสารไม่ได้กำหนด `Menu_name` เป็น UNIQUE (ตามที่ยืนยันไว้ในข้อ C) จึง
    **เช็คซ้ำด้วย logic โปรแกรม** (SELECT ก่อน insert) แทนการพึ่ง constraint
    ของฐานข้อมูล — ทำให้รันซ้ำได้ปลอดภัย ไม่สร้างเมนูซ้ำเวลาเซิร์ฟเวอร์รีสตาร์ท

    Returns:
        จำนวนแถวที่ insert ใหม่จริง (ไม่นับที่ข้ามเพราะมีชื่อซ้ำอยู่แล้ว)
    """
    inserted = 0
    with db_session() as conn:
        existing_names = {
            row["Menu_name"] for row in conn.execute("SELECT Menu_name FROM Menu")
        }
        for item in full_data:
            if item["menu"] in existing_names:
                continue
            ingredient_text = "\n".join(item["ingredients"])
            conn.execute(
                """
                INSERT INTO Menu (Menu_name, Image, ingredient, method)
                VALUES (?, NULL, ?, ?)
                """,
                (item["menu"], ingredient_text, item["method"]),
            )
            existing_names.add(item["menu"])  # กันซ้ำภายใน full_data เองด้วย
            inserted += 1
    return inserted


def get_menu_by_name(menu_name: str) -> MenuRow | None:
    with db_session() as conn:
        row = conn.execute(
            "SELECT * FROM Menu WHERE Menu_name = ?", (menu_name,)
        ).fetchone()
    return _row_to_menu(row) if row else None


def get_menu_by_id(mid: int) -> MenuRow | None:
    with db_session() as conn:
        row = conn.execute("SELECT * FROM Menu WHERE MID = ?", (mid,)).fetchone()
    return _row_to_menu(row) if row else None


def set_menu_image(mid: int, image: str) -> None:
    """อัปเดตชื่อไฟล์/URL รูปภาพของเมนู (เผื่อทำฟีเจอร์อัปโหลดรูปทีหลัง)"""
    with db_session() as conn:
        conn.execute("UPDATE Menu SET Image = ? WHERE MID = ?", (image, mid))


def backfill_missing_images(limit: int = 50) -> int:
    """ดึงรูปจริงจาก Pexels มาใส่ให้เมนูที่ยังไม่มีรูป (Image IS NULL)

    ทำเป็นฟังก์ชันเรียก "ทีละรอบ" แยกต่างหาก (ไม่ได้เรียกอัตโนมัติทุกครั้งที่
    อ่านข้อมูลเมนู) เพราะการเรียก API ภายนอกทุกครั้งที่มีคนเปิดดูเมนูจะทำให้
    ระบบช้าลงมาก และเสี่ยงชน rate limit ของ Pexels เร็วเกินไป — เรียกฟังก์ชันนี้
    ผ่าน endpoint `/api/admin/backfill-images` เป็นครั้งคราวแทน

    Returns:
        จำนวนเมนูที่หารูปเจอและอัปเดตสำเร็จจริง
    """
    from image_service import fetch_food_image_url

    with db_session() as conn:
        rows = conn.execute(
            "SELECT MID, Menu_name FROM Menu WHERE Image IS NULL LIMIT ?", (limit,)
        ).fetchall()
        menus_without_image = [(r["MID"], r["Menu_name"]) for r in rows]

    updated = 0
    for mid, menu_name in menus_without_image:
        image_url = fetch_food_image_url(menu_name)
        if image_url:
            with db_session() as conn:
                conn.execute("UPDATE Menu SET Image = ? WHERE MID = ?", (image_url, mid))
            updated += 1
    return updated


# ---------------------------------------------------------------------------
# Menu_Favorite — เมนูโปรด (many-to-many ระหว่าง User กับ Menu)
# ---------------------------------------------------------------------------


def add_favorite(uid: int, mid: int) -> None:
    """กดถูกใจเมนู — UNIQUE(UID, MID) ที่ยืนยันไว้ (ข้อ A) ทำให้กดซ้ำแล้วไม่เพิ่ม
    แถวใหม่อัตโนมัติอยู่แล้ว ใช้ INSERT OR IGNORE เพื่อไม่ให้ error ตอนกดซ้ำ
    """
    with db_session() as conn:
        conn.execute(
            "INSERT OR IGNORE INTO Menu_Favorite (UID, MID) VALUES (?, ?)",
            (uid, mid),
        )


def remove_favorite(uid: int, mid: int) -> None:
    """ยกเลิกถูกใจ — ลบแถวเดิมออก (ตามพฤติกรรมที่ยืนยันไว้ในข้อ A)"""
    with db_session() as conn:
        conn.execute(
            "DELETE FROM Menu_Favorite WHERE UID = ? AND MID = ?", (uid, mid)
        )


def is_favorite(uid: int, mid: int) -> bool:
    with db_session() as conn:
        row = conn.execute(
            "SELECT 1 FROM Menu_Favorite WHERE UID = ? AND MID = ?", (uid, mid)
        ).fetchone()
    return row is not None


def list_favorites(uid: int) -> list[MenuRow]:
    with db_session() as conn:
        rows = conn.execute(
            """
            SELECT Menu.* FROM Menu
            JOIN Menu_Favorite ON Menu_Favorite.MID = Menu.MID
            WHERE Menu_Favorite.UID = ?
            ORDER BY Menu_Favorite.Favorite_Date DESC
            """,
            (uid,),
        ).fetchall()
    return [_row_to_menu(r) for r in rows]


def list_popular_menus(limit: int = 10) -> list[MenuRow]:
    """เมนู "ยอดนิยม" — จัดอันดับจากทั้งจำนวนกดถูกใจ **และ** คะแนนดาวเฉลี่ย
    (ตามที่ปรับเพิ่มจากเดิมที่ใช้แค่ยอดถูกใจอย่างเดียว)

    สูตรจัดอันดับ: popularity = จำนวนถูกใจ + คะแนนดาวเฉลี่ย (เต็ม 5)
    ตัวอย่าง: เมนู A มี 8 ถูกใจ คะแนนเฉลี่ย 4.5 ดาว -> popularity = 12.5
              เมนู B มี 10 ถูกใจ ไม่มีใครรีวิวเลย -> popularity = 10.0
    (สูตรนี้ปรับน้ำหนักได้ทีหลังถ้าอยากให้ดาวมีผลมากกว่านี้ เช่นคูณ 2 เข้าไป)

    **เรื่อง SQL ที่ต้องระวัง:** ห้าม LEFT JOIN ตาราง Menu_Favorite กับ Review
    ตรงๆ พร้อมกันสองอันแบบ join ธรรมดา เพราะแต่ละเมนูมี favorite หลายแถวและ
    review หลายแถวไม่เท่ากัน — join รวมกันจะเกิด "fan-out" (คูณไขว้กันเป็น
    N×M แถวปลอม) ทำให้ COUNT/AVG ผิดเพี้ยนทันที จึงต้อง aggregate แต่ละตาราง
    แยกเป็น subquery ก่อน แล้วค่อย join ผลลัพธ์ที่ aggregate แล้วเข้าด้วยกัน
    """
    with db_session() as conn:
        rows = conn.execute(
            """
            SELECT
                Menu.MID, Menu.Menu_name, Menu.Image, Menu.ingredient, Menu.method,
                COALESCE(fav.favorite_count, 0) AS favorite_count,
                COALESCE(rev.avg_score, 0) AS avg_review_score,
                COALESCE(rev.review_count, 0) AS review_count
            FROM Menu
            LEFT JOIN (
                SELECT MID, COUNT(*) AS favorite_count FROM Menu_Favorite GROUP BY MID
            ) fav ON fav.MID = Menu.MID
            LEFT JOIN (
                SELECT MID, AVG(Score) AS avg_score, COUNT(*) AS review_count FROM Review GROUP BY MID
            ) rev ON rev.MID = Menu.MID
            ORDER BY (COALESCE(fav.favorite_count, 0) + COALESCE(rev.avg_score, 0)) DESC,
                     Menu.Menu_name ASC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()

    return [
        MenuRow(
            mid=r["MID"],
            menu_name=r["Menu_name"],
            image=r["Image"],
            ingredient=r["ingredient"],
            method=r["method"],
            average_score=round(r["avg_review_score"], 2) if r["review_count"] > 0 else None,
            review_count=r["review_count"],
        )
        for r in rows
    ]


# ---------------------------------------------------------------------------
# Review — คะแนน 1-5 ดาว + คอมเมนต์ (D4 ในเอกสาร)
# ---------------------------------------------------------------------------


def upsert_review(uid: int, mid: int, score: int, comment: str | None = None) -> None:
    """ให้คะแนนเมนู — ถ้าคนนี้เคยรีวิวเมนูนี้แล้วจะ "แก้ไข" รีวิวเดิมแทนการสร้าง
    แถวใหม่ (ตามที่ยืนยันไว้ในข้อ B — UNIQUE(UID, MID) กำกับไว้ในตารางอยู่แล้ว)
    """
    if not 1 <= score <= 5:
        raise ValueError("คะแนนต้องอยู่ระหว่าง 1-5")

    with db_session() as conn:
        conn.execute(
            """
            INSERT INTO Review (UID, MID, Score, Comment)
            VALUES (?, ?, ?, ?)
            ON CONFLICT (UID, MID)
            DO UPDATE SET Score = excluded.Score, Comment = excluded.Comment
            """,
            (uid, mid, score, comment),
        )


def get_menu_review_summary(mid: int) -> dict[str, Any]:
    """คืนค่าเฉลี่ยคะแนน + จำนวนรีวิวของเมนูนี้"""
    with db_session() as conn:
        row = conn.execute(
            "SELECT AVG(Score) AS avg_score, COUNT(*) AS count FROM Review WHERE MID = ?",
            (mid,),
        ).fetchone()
    return {
        "average_score": round(row["avg_score"], 2) if row["avg_score"] is not None else None,
        "review_count": row["count"],
    }


def list_reviews(mid: int) -> list[dict[str, Any]]:
    """รายการรีวิวทั้งหมดของเมนูนี้ พร้อมชื่อผู้รีวิว (JOIN กับตาราง User) —
    เรียงรีวิวล่าสุดขึ้นก่อน
    """
    with db_session() as conn:
        rows = conn.execute(
            """
            SELECT Review.UID, User.Fullname, Review.Score, Review.Comment, Review.Review_Date
            FROM Review
            JOIN User ON User.UID = Review.UID
            WHERE Review.MID = ?
            ORDER BY Review.Review_Date DESC, Review.RID DESC
            """,
            (mid,),
        ).fetchall()
    return [
        {
            "uid": r["UID"],
            "fullname": r["Fullname"],
            "score": r["Score"],
            "comment": r["Comment"],
            "review_date": r["Review_Date"],
        }
        for r in rows
    ]
