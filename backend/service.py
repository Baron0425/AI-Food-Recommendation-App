"""
Service layer: โหลด/เทรน/แคชโมเดล แล้วเปิดฟังก์ชันค้นหาให้ชั้น API เรียกใช้

แยกไฟล์นี้ออกจาก `api_server.py` โดยตั้งใจ เพื่อให้ logic หลัก (โหลดข้อมูล,
เทรนโมเดล, ค้นหา) ไม่ผูกกับเว็บเฟรมเวิร์กใดๆ เลย — ทดสอบได้ตรงๆ ด้วย
`pytest`/สคริปต์ธรรมดา โดยไม่ต้องรันเซิร์ฟเวอร์ และถ้าวันหลังอยากเปลี่ยนจาก
FastAPI ไปเฟรมเวิร์กอื่น ก็แก้แค่ `api_server.py` ไฟล์เดียว

**เรื่องแคช (สำคัญมากสำหรับการเชื่อมแอพจริง):** โค้ดเดิมโหลด dataset จาก
Hugging Face และเทรน KNN ใหม่ทุกครั้งที่โปรแกรมเริ่มทำงาน ซึ่งใช้เวลาหลาย
วินาทีถึงหลักสิบวินาที ถ้าเอาไปทำเป็น API แล้วเซิร์ฟเวอร์รีสตาร์ทบ่อยๆ (เช่น
ตอน deploy หรือ auto-reload ตอน dev) แอพ Flutter จะต้องรอนานทุกครั้ง จึงเพิ่ม
การแคชผลลัพธ์ทั้งหมดลงไฟล์ด้วย `joblib` — โหลดครั้งแรกช้า แต่ครั้งต่อไปเร็ว
ทันที (ไม่ต้องต่อเน็ตหรือเทรนใหม่) จนกว่าจะลบไฟล์แคชทิ้ง
"""
from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Any

from data_loader import load_data
from database import init_db
from evaluation import precision_at_k
from feature_engineering import build_features
from menu_repository import sync_menus_from_engine
from model import load_model, save_model, train_knn
from recommender import recommend_menu, search_by_ingredients, search_by_name

logger = logging.getLogger(__name__)

CACHE_PATH = os.environ.get("RECIPE_ENGINE_CACHE", "engine_cache.joblib")


@dataclass
class Engine:
    menu_names: list[str]
    menu_names_normalized: list[str]
    full_data: list[dict[str, Any]]
    menu_vectorizer: Any
    ing_vectorizer: Any
    knn_menu: Any
    knn_ing: Any

    @property
    def menu_count(self) -> int:
        return len(self.menu_names)


def _build_engine() -> Engine:
    menu_names, menu_names_normalized, ingredient_texts, full_data = load_data()

    if not menu_names:
        raise RuntimeError("ไม่พบข้อมูลเมนูใด ๆ หลังจากทำความสะอาดข้อมูล — ตรวจสอบ dataset")

    X_menu, X_ing, menu_vectorizer, ing_vectorizer = build_features(
        menu_names, ingredient_texts
    )
    knn_menu = train_knn(X_menu)
    knn_ing = train_knn(X_ing)

    return Engine(
        menu_names=menu_names,
        menu_names_normalized=menu_names_normalized,
        full_data=full_data,
        menu_vectorizer=menu_vectorizer,
        ing_vectorizer=ing_vectorizer,
        knn_menu=knn_menu,
        knn_ing=knn_ing,
    )


def load_or_build_engine(cache_path: str = CACHE_PATH, force_rebuild: bool = False) -> Engine:
    """โหลด engine จากแคชถ้ามี ไม่งั้นสร้างใหม่แล้วบันทึกแคชไว้ใช้ครั้งถัดไป

    ตั้ง `force_rebuild=True` (หรือลบไฟล์แคชทิ้งเอง) เมื่อ dataset หรือโค้ด
    เตรียมข้อมูล/ฟีเจอร์เปลี่ยนไป ไม่งั้นระบบจะยังใช้ผลลัพธ์เก่าจากแคชอยู่
    """
    if not force_rebuild and os.path.exists(cache_path):
        logger.info("Loading engine from cache: %s", cache_path)
        try:
            return load_model(cache_path)
        except Exception:  # noqa: BLE001 - แคชเสีย/ไม่ตรงเวอร์ชัน ให้ build ใหม่แทน error ทิ้งเลย
            logger.warning("Cache at %s is invalid — rebuilding from scratch", cache_path)

    logger.info("Building engine from scratch (this calls out to Hugging Face + trains KNN)...")
    engine = _build_engine()
    save_model(engine, cache_path)
    logger.info("Engine cached to %s", cache_path)
    return engine


# --- singleton เดียวที่ทั้งแอพใช้ร่วมกัน (โหลดครั้งเดียวตอนโปรเซสเริ่ม) ---
_engine: Engine | None = None


def get_engine() -> Engine:
    global _engine
    if _engine is None:
        _engine = load_or_build_engine()
        # ให้ตาราง `menu` ใน SQLite มีข้อมูลตรงกับที่โมเดล KNN ใช้อยู่เสมอ —
        # จำเป็นเพราะ favorite/rating ต้องอ้างอิง menu_id ที่มีอยู่จริงใน DB
        # `init_db` และ `sync_menus_from_engine` ทั้งคู่ idempotent (เรียกซ้ำได้
        # ปลอดภัย ไม่สร้างข้อมูลซ้ำ) จึงเรียกทุกครั้งที่ engine ถูกสร้าง/โหลดได้เลย
        init_db()
        inserted = sync_menus_from_engine(_engine.full_data)
        if inserted:
            logger.info("Synced %d new menus into the database", inserted)
    return _engine


def search_auto(query: str, top_k: int = 3) -> list[dict[str, Any]]:
    """ค้นหาแบบอัตโนมัติ (ตรวจเองว่าเป็นชื่อเมนูหรือวัตถุดิบ) — ใช้กับช่องค้นหาเดียวในแอพ"""
    engine = get_engine()
    return recommend_menu(
        query=query,
        menu_vectorizer=engine.menu_vectorizer,
        ing_vectorizer=engine.ing_vectorizer,
        knn_menu=engine.knn_menu,
        knn_ing=engine.knn_ing,
        menu_names=engine.menu_names,
        menu_names_normalized=engine.menu_names_normalized,
        full_data=engine.full_data,
        top_k=top_k,
    )


def search_name(query: str, top_k: int = 3) -> list[dict[str, Any]]:
    """ค้นหาเฉพาะด้วยชื่อเมนู (ใช้กับ endpoint /api/search/name)"""
    engine = get_engine()
    return search_by_name(
        query, engine.menu_vectorizer, engine.knn_menu, engine.menu_names,
        engine.menu_names_normalized, engine.full_data, top_k,
    )


def search_ingredients(query: str, top_k: int = 3) -> list[dict[str, Any]]:
    """ค้นหาเฉพาะด้วยวัตถุดิบ (ใช้กับ endpoint /api/recommend)"""
    engine = get_engine()
    return search_by_ingredients(
        query, engine.ing_vectorizer, engine.knn_ing, engine.menu_names,
        engine.full_data, top_k,
    )


def evaluate_precision(query: str, results: list[dict[str, Any]], k: int = 3) -> float:
    engine = get_engine()
    return precision_at_k(query, results, engine.menu_names, k)
