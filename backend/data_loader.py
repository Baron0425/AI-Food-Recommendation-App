"""
Data loading & text preprocessing สำหรับระบบแนะนำสูตรอาหารไทยด้วย AI

โมดูลนี้รับผิดชอบ:
    1. โหลดชุดข้อมูล ThaiFood จาก Hugging Face
    2. แยก "วัตถุดิบ" ออกจาก "วิธีทำ" ให้สะอาด
    3. Normalize ข้อความ (ไทย/อังกฤษ/ตัวเลข) ให้สม่ำเสมอ เพื่อใช้กับ
       vectorizer และการเทียบคำค้นหา

การแก้ไขจากโค้ดต้นฉบับ:
    - regex เดิม (`re.sub(r"-\\s*.+", "", text)` และ
      `re.findall(r"-\\s*(.+)", text)`) ไม่ได้ยึดต้นบรรทัด (`^`) จึงมีโอกาส
      จับคู่เครื่องหมาย "-" ที่อยู่กลางประโยคของ "วิธีทำ" ผิดพลาด (เช่น
      "ผัด-ทอด จนสุก" จะถูกตัดข้อความส่วนหลังทิ้งไปด้วย) โค้ดนี้ใช้
      `re.MULTILINE` ผูกกับ `^`/`$` เพื่อให้จับเฉพาะบรรทัดที่ขึ้นต้นด้วย "-"
      จริง ๆ เท่านั้น
    - เพิ่มการข้ามเมนูที่ "วิธีทำ" ว่างเปล่าหลัง clean (เดิมไม่ได้เช็ก
      อาจทำให้มีเมนูที่แนะนำแล้วไม่มีวิธีทำให้ผู้ใช้เห็น)
"""
from __future__ import annotations

import logging
import re
from typing import Any

from datasets import load_dataset

logger = logging.getLogger(__name__)

# ไลบรารี datasets/huggingface_hub จะ log คำขอ HTTP ทุกครั้งที่ระดับ INFO ทำให้
# หน้าจอรกตอนโหลด dataset ครั้งแรก (ครั้งถัดไปจะอ่านจาก cache ในเครื่อง จึง
# ไม่มี request เยอะขนาดนี้อีก) — ปรับให้แสดงเฉพาะ WARNING ขึ้นไปเพื่อความสะอาดตา
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("huggingface_hub").setLevel(logging.WARNING)

# บรรทัดวัตถุดิบในชุดข้อมูลขึ้นต้นด้วย "-" เช่น "- ไก่ 200 กรัม"
_INGREDIENT_LINE_RE = re.compile(r"^-\s*(.+)$", re.MULTILINE)
_HEADER_LINE_RE = re.compile(r"^#.*$", re.MULTILINE)
_MULTI_NEWLINE_RE = re.compile(r"\n+")
_MULTI_SPACE_RE = re.compile(r"\s+")
_NON_THAI_ENG_NUM_RE = re.compile(r"[^\u0E00-\u0E7Fa-z0-9\s]")


def clean_method(text: str) -> str:
    """ทำความสะอาดข้อความ 'วิธีทำ'

    ตัดบรรทัด header (ขึ้นต้นด้วย #) และบรรทัดวัตถุดิบ (ขึ้นต้นด้วย -) ออก
    แล้วยุบบรรทัดว่าง/ช่องว่างส่วนเกินให้เหลือค่าเดียว
    """
    text = _HEADER_LINE_RE.sub("", text)
    text = _INGREDIENT_LINE_RE.sub("", text)
    text = _MULTI_NEWLINE_RE.sub("\n", text)
    text = _MULTI_SPACE_RE.sub(" ", text)
    return text.strip()


def extract_ingredients(text: str) -> list[str]:
    """ดึงรายการวัตถุดิบจากบรรทัดที่ขึ้นต้นด้วย '-' เท่านั้น

    ใช้ `^`/`$` ร่วมกับ `re.MULTILINE` เพื่อยึดต้น/ท้ายบรรทัดจริง ป้องกันไม่ให้
    จับคู่ผิดกับเครื่องหมาย '-' ที่ปนอยู่กลางประโยคของส่วนอื่น
    """
    return [line.strip() for line in _INGREDIENT_LINE_RE.findall(text) if line.strip()]


def normalize_text(text: str) -> str:
    """Normalize ข้อความ: lowercase + เก็บเฉพาะอักษรไทย/อังกฤษ/ตัวเลข/ช่องว่าง

    ใช้จุดเดียวกันทั้งตอนเตรียมข้อมูลสำหรับเทรน และตอนรับคำค้นหาจากผู้ใช้
    เพื่อให้ผลลัพธ์การเทียบคำสม่ำเสมอ ไม่ขึ้นกับตัวพิมพ์เล็ก-ใหญ่หรือ
    เครื่องหมายวรรคตอนที่พิมพ์ปนมา
    """
    text = text.lower().strip()
    text = _NON_THAI_ENG_NUM_RE.sub("", text)
    text = _MULTI_SPACE_RE.sub(" ", text)
    return text.strip()


def load_data() -> tuple[list[str], list[str], list[str], list[dict[str, Any]]]:
    """โหลดและเตรียมชุดข้อมูล ThaiFood

    Returns:
        menu_names: ชื่อเมนูตามต้นฉบับ (ใช้แสดงผลให้ผู้ใช้เห็น)
        menu_names_normalized: ชื่อเมนูที่ normalize แล้ว (ใช้ค้นหา/เทียบคำ)
        ingredient_texts: ข้อความวัตถุดิบที่ normalize แล้ว (ใช้ vectorize)
        full_data: รายละเอียดครบของแต่ละเมนู (menu, ingredients, method)
    """
    logger.info("Loading dataset...")
    dataset = load_dataset("pythainlp/thai_food_v1.0")

    menu_names: list[str] = []
    menu_names_normalized: list[str] = []
    ingredient_texts: list[str] = []
    full_data: list[dict[str, Any]] = []

    skipped_no_menu_or_text = 0
    skipped_no_ingredients = 0
    skipped_no_method = 0

    for row in dataset["train"]:
        menu = (row.get("name") or "").strip()
        text = row.get("text") or ""

        if not menu or not text:
            skipped_no_menu_or_text += 1
            continue

        ingredients = extract_ingredients(text)
        if not ingredients:
            skipped_no_ingredients += 1
            continue

        method_clean = clean_method(text)
        if not method_clean:
            skipped_no_method += 1
            continue

        menu_names.append(menu)
        menu_names_normalized.append(normalize_text(menu))
        ingredient_texts.append(normalize_text(" ".join(ingredients)))
        full_data.append(
            {
                "menu": menu,
                "ingredients": ingredients,
                "method": method_clean,
            }
        )

    logger.info("Total menus loaded: %d", len(menu_names))
    if skipped_no_menu_or_text or skipped_no_ingredients or skipped_no_method:
        logger.info(
            "Skipped rows -> no menu/text: %d, no ingredients: %d, no method: %d",
            skipped_no_menu_or_text,
            skipped_no_ingredients,
            skipped_no_method,
        )

    return menu_names, menu_names_normalized, ingredient_texts, full_data
