"""
สร้างฟีเจอร์ (vector) จากข้อความชื่อเมนูและวัตถุดิบ สำหรับใช้กับ KNN

**จุดที่แก้ไขจากโค้ดเดิม (สำคัญที่สุดของไฟล์นี้):**
`CountVectorizer` ของ scikit-learn ใช้ `token_pattern` เริ่มต้นคือ
`r"(?u)\\b\\w\\w+\\b"` ซึ่งออกแบบมาสำหรับภาษาที่มีช่องว่างคั่นระหว่างคำ เช่น
ภาษาอังกฤษ แต่ **ภาษาไทยเขียนติดกันไม่มีช่องว่างคั่นคำ** ผลคือ regex ตัวนี้จะ
จับข้อความไทยทั้งประโยคที่ไม่มีช่องว่างเป็น "หนึ่ง token" แทนที่จะเป็นคำ ๆ
ทำให้ `ngram_range=(1, 2)` ที่ตั้งใจจะให้จับคู่คำ (word bigram) แทบไม่มี
ความหมายกับภาษาไทยเลย และ KNN ที่คำนวณจากเวกเตอร์นี้ก็จะไม่แม่นยำ

วิธีแก้คือตัดคำภาษาไทยเองก่อนด้วย `pythainlp` แล้วส่ง token ที่ตัดแล้วให้
`CountVectorizer` ผ่านพารามิเตอร์ `tokenizer` (พร้อมปิด `token_pattern` เดิม)
"""
from __future__ import annotations

import warnings

from sklearn.feature_extraction.text import CountVectorizer

try:
    from pythainlp.tokenize import word_tokenize

    def _thai_tokenizer(text: str) -> list[str]:
        return [w for w in word_tokenize(text, engine="newmm") if w.strip()]

    _TOKENIZER_AVAILABLE = True

except ImportError:  # pragma: no cover - fallback เมื่อไม่ได้ติดตั้ง pythainlp
    _TOKENIZER_AVAILABLE = False

    def _thai_tokenizer(text: str) -> list[str]:
        # fallback แบบง่าย: แบ่งด้วยช่องว่าง — ใช้ได้กับคำอังกฤษ/ตัวเลขที่มี
        # เว้นวรรคคั่น แต่ "ไม่เหมาะ" กับประโยคภาษาไทยล้วนที่ไม่มีช่องว่าง
        return text.split()


if not _TOKENIZER_AVAILABLE:
    warnings.warn(
        "ไม่พบไลบรารี pythainlp — ระบบจะตัดคำด้วยการแบ่งช่องว่างแบบง่าย "
        "ซึ่งจะทำให้การค้นหา/แนะนำเมนูภาษาไทยไม่แม่นยำ "
        "ติดตั้งด้วย `pip install pythainlp` แล้วรันใหม่เพื่อผลลัพธ์ที่ถูกต้อง",
        RuntimeWarning,
        stacklevel=2,
    )


def _make_vectorizer() -> CountVectorizer:
    return CountVectorizer(
        tokenizer=_thai_tokenizer,
        token_pattern=None,  # จำเป็นต้องปิด ไม่งั้น sklearn จะ warn/ยังพยายามใช้ regex เดิมซ้อน
        ngram_range=(1, 2),
        binary=True,
    )


def build_features(menu_names: list[str], ingredient_texts: list[str]):
    """สร้าง vectorizer + เมทริกซ์ฟีเจอร์แยกสำหรับ 'ชื่อเมนู' และ 'วัตถุดิบ'

    ใช้ vectorizer คนละตัวกันเพราะ vocabulary ของชื่อเมนูกับวัตถุดิบต่างกัน
    มาก การรวมกันจะทำให้พื้นที่เวกเตอร์ใหญ่เกินจำเป็นและลดคุณภาพของ KNN
    """
    menu_vectorizer = _make_vectorizer()
    ingredient_vectorizer = _make_vectorizer()

    X_menu = menu_vectorizer.fit_transform(menu_names)
    X_ing = ingredient_vectorizer.fit_transform(ingredient_texts)

    return X_menu, X_ing, menu_vectorizer, ingredient_vectorizer
