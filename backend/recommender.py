"""
Logic การค้นหา/แนะนำเมนูอาหาร

**บั๊กสำคัญที่แก้ในไฟล์นี้:** โค้ดเดิมของ `recommend_menu()` รับพารามิเตอร์
ไม่ตรงกับที่ `main.py` เรียกใช้ — `main.py` ส่ง `menu_names_normalized`
เป็นอาร์กิวเมนต์ตัวที่ 7 (ก่อน `full_data`) แต่ signature เดิมของฟังก์ชันนี้
ไม่มีพารามิเตอร์นี้เลย ผลคือค่าที่ส่งมาจะเลื่อนตำแหน่งกัน:
`menu_names_normalized` ไปตกที่พารามิเตอร์ `full_data` และ `full_data`
(list ของ dict) ไปตกที่พารามิเตอร์ `top_k` (ควรเป็น int) ทำให้
`knn.kneighbors(..., n_neighbors=top_k)` พังทันทีเพราะ `top_k` กลายเป็น list
ไม่ใช่ตัวเลข โค้ดนี้แก้โดยเพิ่มพารามิเตอร์ `menu_names_normalized` ให้ตรงกับ
ที่ `main.py` เรียกจริง

**ของใหม่ที่เพิ่มเข้ามา:**
    - `menu_names_normalized` ที่โค้ดเดิมสร้างไว้แต่ไม่เคยถูกใช้งานเลย ตอนนี้
      ใช้จริงสำหรับค้นหาแบบ exact match และ partial/substring match ก่อนจะ
      fallback ไปใช้ KNN — ทำให้พิมพ์ชื่อเมนูไม่ครบคำก็ยังค้นเจอ
    - การค้นหาด้วยวัตถุดิบตอนนี้ normalize คำค้นหาก่อน vectorize เสมอ (โค้ด
      เดิมส่ง query ดิบเข้า `ing_vectorizer.transform([query])` ทั้งที่ตอน
      เทรนใช้ข้อความที่ normalize แล้ว ทำให้ vocabulary ไม่ตรงกัน)
    - ป้องกันกรณีคำค้นหาไม่มีคำใดอยู่ใน vocabulary เลย (เวกเตอร์เป็นศูนย์ทั้งแถว)
      ซึ่งเดิมจะส่งเข้า KNN ตรง ๆ แล้วได้ระยะห่าง/คะแนนที่ไม่มีความหมาย
"""
from __future__ import annotations

from typing import Any

from data_loader import normalize_text


def _build_result(
    idx: int, score: float, menu_names: list[str], full_data: list[dict[str, Any]]
) -> dict[str, Any]:
    return {
        "menu": menu_names[idx],
        "score": round(float(score), 4),
        "ingredients": full_data[idx]["ingredients"],
        "method": full_data[idx]["method"],
    }


def _knn_search(
    query_text: str,
    vectorizer,
    knn,
    menu_names: list[str],
    full_data: list[dict[str, Any]],
    top_k: int,
    exclude_idx: set[int] | None = None,
) -> list[dict[str, Any]]:
    """ค้นหาความใกล้เคียงเชิงเวกเตอร์ด้วย KNN คืนผลลัพธ์สูงสุด top_k รายการ"""
    if top_k <= 0:
        return []

    query_vec = vectorizer.transform([query_text])

    # ถ้าคำค้นหาไม่มีคำไหนอยู่ใน vocabulary ที่เทรนไว้เลย เวกเตอร์จะเป็นศูนย์
    # ทั้งแถว ระยะห่าง cosine กับข้อมูลทุกจุดจะไม่มีความหมาย (สุ่ม/คงที่)
    # จึงคืนลิสต์ว่างแทนที่จะส่งต่อให้ KNN
    if query_vec.nnz == 0:
        return []

    n_candidates = min(top_k + len(exclude_idx or ()), knn.n_samples_fit_)
    if n_candidates <= 0:
        return []

    distances, indices = knn.kneighbors(query_vec, n_neighbors=n_candidates)

    results = []
    for dist, idx in zip(distances[0], indices[0]):
        if exclude_idx and idx in exclude_idx:
            continue
        results.append(_build_result(idx, 1 - dist, menu_names, full_data))
        if len(results) >= top_k:
            break
    return results


def search_by_name(
    query: str,
    menu_vectorizer,
    knn_menu,
    menu_names: list[str],
    menu_names_normalized: list[str],
    full_data: list[dict[str, Any]],
    top_k: int = 3,
) -> list[dict[str, Any]]:
    """ค้นหาเมนูจากชื่อ ตามลำดับความสำคัญ: ตรงเป๊ะ -> มีคำค้นหาอยู่ในชื่อ -> ใกล้เคียงเชิงเวกเตอร์"""
    normalized_query = normalize_text(query)
    if not normalized_query:
        return []

    # 1) ตรงเป๊ะ: เอาเมนูนั้นเป็นอันดับ 1 แล้วเติมเมนูใกล้เคียงจาก KNN ให้ครบ top_k
    if normalized_query in menu_names_normalized:
        idx = menu_names_normalized.index(normalized_query)
        exact = _build_result(idx, 1.0, menu_names, full_data)
        rest = _knn_search(
            menu_names[idx], menu_vectorizer, knn_menu, menu_names, full_data,
            top_k - 1, exclude_idx={idx},
        )
        return [exact] + rest

    # 2) partial/substring match: ผู้ใช้พิมพ์ชื่อไม่ครบ (เช่น "ผัดไท" -> "ผัดไทยกุ้งสด")
    #    เรียงตามความยาวชื่อ (สั้น = ใกล้เคียงกับคำค้นหามากกว่า)
    partial_matches = [
        i for i, name in enumerate(menu_names_normalized) if normalized_query in name
    ]
    if partial_matches:
        partial_matches.sort(key=lambda i: len(menu_names_normalized[i]))
        return [_build_result(i, 1.0, menu_names, full_data) for i in partial_matches[:top_k]]

    # 3) fallback: ไม่เจอทั้งตรงเป๊ะและ substring -> ใช้ความใกล้เคียงเชิงเวกเตอร์
    return _knn_search(normalized_query, menu_vectorizer, knn_menu, menu_names, full_data, top_k)


def search_by_ingredients(
    query: str,
    ing_vectorizer,
    knn_ing,
    menu_names: list[str],
    full_data: list[dict[str, Any]],
    top_k: int = 3,
) -> list[dict[str, Any]]:
    """ค้นหาเมนูจากรายการวัตถุดิบที่ผู้ใช้กรอก (normalize ก่อนเสมอให้ตรงกับตอนเทรน)"""
    normalized_query = normalize_text(query)
    if not normalized_query:
        return []
    return _knn_search(normalized_query, ing_vectorizer, knn_ing, menu_names, full_data, top_k)


def recommend_menu(
    query: str,
    menu_vectorizer,
    ing_vectorizer,
    knn_menu,
    knn_ing,
    menu_names: list[str],
    menu_names_normalized: list[str],
    full_data: list[dict[str, Any]],
    top_k: int = 3,
) -> list[dict[str, Any]]:
    """จุดเข้าใช้งานหลัก: ตัดสินใจอัตโนมัติว่าผู้ใช้ค้นหาด้วยชื่อเมนูหรือวัตถุดิบ

    ถ้าคำค้นหาตรง หรือเป็นส่วนหนึ่งของชื่อเมนูใด ๆ ในระบบ ถือว่าค้นหาด้วยชื่อเมนู
    ไม่เช่นนั้นถือว่าเป็นการค้นหาด้วยรายการวัตถุดิบ
    """
    normalized_query = normalize_text(query)
    if not normalized_query:
        return []

    is_name_search = any(normalized_query in name for name in menu_names_normalized)

    if is_name_search:
        return search_by_name(
            query, menu_vectorizer, knn_menu, menu_names, menu_names_normalized,
            full_data, top_k,
        )

    return search_by_ingredients(query, ing_vectorizer, knn_ing, menu_names, full_data, top_k)
