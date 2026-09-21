"""CLI สำหรับทดสอบระบบแนะนำเมนูอาหารไทยด้วย AI (KNN)

จุดที่แก้จากโค้ดเดิม: เดิมไฟล์นี้เรียก `recommend_menu(...)` โดยส่ง
`menu_names_normalized` แทรกเข้ามาเป็นอาร์กิวเมนต์ตัวที่ 7 ทั้งที่
`recommender.py` เวอร์ชันเดิมไม่มีพารามิเตอร์นี้ ทำให้ค่าทุกตัวหลังจากนั้น
เลื่อนตำแหน่งผิด (ดูรายละเอียดเต็มในคอมเมนต์ของ `recommender.py`) เวอร์ชันนี้
เรียกด้วยคีย์เวิร์ดอาร์กิวเมนต์ (keyword arguments) แทนตำแหน่งล้วน ๆ
เพื่อป้องกันบั๊กลักษณะนี้ไม่ให้เกิดซ้ำในอนาคตแม้ signature จะเปลี่ยนอีก
"""
from __future__ import annotations

import logging

from data_loader import load_data
from evaluation import precision_at_k
from feature_engineering import build_features
from model import train_knn
from recommender import recommend_menu

logging.basicConfig(level=logging.INFO, format="%(message)s")
logger = logging.getLogger(__name__)


def print_results(results: list[dict]) -> None:
    if not results:
        print("ไม่พบเมนูที่เกี่ยวข้อง")
        return

    for i, r in enumerate(results, start=1):
        print(f"\n#{i} {r['menu']}  score: {r['score']:.4f}")
        print("วัตถุดิบ:")
        for ing in r["ingredients"][:5]:
            print("-", ing)
        print("\nวิธีทำ:")
        print(r["method"][:1000])
        print("-" * 40)


def main() -> None:
    menu_names, menu_names_normalized, ingredient_texts, full_data = load_data()

    if not menu_names:
        logger.error("ไม่พบข้อมูลเมนูใด ๆ หลังจากทำความสะอาดข้อมูล — ตรวจสอบ dataset")
        return

    X_menu, X_ing, menu_vectorizer, ing_vectorizer = build_features(
        menu_names, ingredient_texts
    )

    knn_menu = train_knn(X_menu)
    knn_ing = train_knn(X_ing)

    print("พิมพ์ชื่อเมนู หรือ วัตถุดิบที่ต้องการค้นหา (พิมพ์ exit เพื่อออก)")

    while True:
        query = input("\nSearch Menu: ").strip()

        if not query:
            continue
        if query.lower() == "exit":
            break

        results = recommend_menu(
            query=query,
            menu_vectorizer=menu_vectorizer,
            ing_vectorizer=ing_vectorizer,
            knn_menu=knn_menu,
            knn_ing=knn_ing,
            menu_names=menu_names,
            menu_names_normalized=menu_names_normalized,
            full_data=full_data,
            top_k=3,
        )

        print_results(results)

        precision = precision_at_k(query, results, menu_names, k=3)
        print(f"\nPrecision@3: {precision:.2f}")


if __name__ == "__main__":
    main()
