"""
วัด Precision@K ของผลลัพธ์ที่ระบบแนะนำ เทียบกับคำค้นหาของผู้ใช้

แก้ไขจากโค้ดเดิม: เดิมเทียบ `query` กับ `menu_names`/`ingredients` แบบดิบ ๆ
โดยไม่ normalize ทำให้ผลลัพธ์ผิดพลาดได้ง่ายจากตัวพิมพ์เล็ก-ใหญ่หรือช่องว่าง/
เครื่องหมายวรรคตอนที่ไม่ตรงกัน (เช่น query="ผัดไทย " กับเมนู "ผัดไทย" จะไม่ถูก
นับว่าตรงกัน เพราะมีช่องว่างท้ายคำต่างกัน) ตอนนี้ normalize ทั้งสองฝั่งด้วย
ฟังก์ชันเดียวกับที่ใช้ตอนเตรียมข้อมูล/ค้นหาจริง เพื่อให้การเทียบสม่ำเสมอ
"""
from __future__ import annotations

from data_loader import normalize_text


def precision_at_k(
    query: str, results: list[dict], menu_names: list[str], k: int = 3
) -> float:
    if not results:
        return 0.0

    normalized_query = normalize_text(query)
    query_words = normalized_query.split()
    normalized_menu_names = [normalize_text(m) for m in menu_names]

    actual_k = min(k, len(results))
    is_name_search = any(normalized_query in name for name in normalized_menu_names)

    relevant = 0
    for r in results[:actual_k]:
        if is_name_search:
            if normalized_query in normalize_text(r["menu"]):
                relevant += 1
        else:
            ingredients_text = normalize_text(" ".join(r["ingredients"]))
            match_count = sum(word in ingredients_text for word in query_words)
            if match_count >= 2:
                relevant += 1

    return relevant / actual_k
