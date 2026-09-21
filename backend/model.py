"""ฝึก/บันทึก/โหลดโมเดล K-Nearest Neighbors สำหรับหาความใกล้เคียงของเวกเตอร์"""
from __future__ import annotations

import joblib
from sklearn.neighbors import NearestNeighbors


def train_knn(X, n_neighbors: int = 10, metric: str = "cosine") -> NearestNeighbors:
    """ฝึกโมเดล KNN บนเมทริกซ์ฟีเจอร์ X

    `n_neighbors` ที่ตั้งตอนเทรนเป็นเพียงค่าเริ่มต้น เวลาค้นหาจริงเราระบุ
    `n_neighbors` ให้ `.kneighbors(...)` แยกต่างหากตาม `top_k` ที่ต้องการเสมอ
    (ดู `recommender.py`) จึงตั้งค่าเริ่มต้นไว้สูงกว่าจำนวนที่มักใช้แสดงผล
    (เช่น top_k=3) เผื่อกรณีอยากปรับ top_k ทีหลังโดยไม่ต้องเทรนใหม่ — แต่ต้อง
    ไม่เกินจำนวนตัวอย่างทั้งหมดที่มี ไม่งั้น `NearestNeighbors.fit` จะ error
    """
    n_neighbors = min(n_neighbors, X.shape[0])
    knn = NearestNeighbors(n_neighbors=n_neighbors, metric=metric)
    knn.fit(X)
    return knn


def save_model(obj, path: str) -> None:
    """บันทึกโมเดล/vectorizer ลงไฟล์ เพื่อไม่ต้องเทรนใหม่ทุกครั้งที่รันโปรแกรม"""
    joblib.dump(obj, path)


def load_model(path: str):
    """โหลดโมเดล/vectorizer ที่บันทึกไว้ก่อนหน้า"""
    return joblib.load(path)
