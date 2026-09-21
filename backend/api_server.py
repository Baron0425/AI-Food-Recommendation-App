"""
REST API (FastAPI) สำหรับให้แอพ Flutter เรียกใช้ระบบแนะนำเมนูอาหาร

ทำไมเลือก FastAPI: เขียนน้อย, มี type hint/validation ในตัว (Pydantic),
ได้ Swagger UI (`/docs`) มาฟรีให้เทสต์ API ผ่านเบราว์เซอร์ได้ทันทีโดยไม่ต้องใช้
Postman และ async ได้ถ้าจำเป็นต้องขยายทีหลัง — ถ้าทีมถนัด Flask/Django มากกว่า
บอกได้ ปรับให้ได้เหมือนกันเพราะ business logic ทั้งหมดอยู่ใน `service.py`
แยกออกมาแล้ว ไฟล์นี้เป็นแค่ชั้น "แปลง HTTP request เป็นเรียกฟังก์ชัน" เท่านั้น

Endpoints (อิงจากที่ระบุไว้ในเอกสารโครงงาน บทที่ 3):
    GET  /health              เช็คว่าเซิร์ฟเวอร์/โมเดลพร้อมใช้งานหรือไม่
    GET  /api/search           ค้นหาอัตโนมัติ (เดาเองว่าเป็นชื่อเมนูหรือวัตถุดิบ)
                                — endpoint นี้เหมาะกับช่องค้นหาช่องเดียวในแอพ
    GET  /api/search/name      ค้นหาเฉพาะด้วยชื่อเมนู
    POST /api/recommend        แนะนำเมนูจากรายการวัตถุดิบที่ผู้ใช้กรอก

Endpoints ใหม่ (STEP 4-7 — Authentication):
    POST   /api/auth/register  สมัครสมาชิกด้วย Email + Password
    POST   /api/auth/login     ล็อกอินด้วย Email + Password -> คืน JWT
    POST   /api/auth/google    ล็อกอิน/สมัครสมาชิกผ่าน Google OAuth -> คืน JWT
    POST   /api/auth/logout    Logout (JWT เป็น stateless — ลบ token ฝั่ง client เอง)
    GET    /api/auth/me        ดึงข้อมูลผู้ใช้ปัจจุบัน (ต้องส่ง Bearer token)
    PUT    /api/auth/me        แก้ไขข้อมูลส่วนตัว (ต้องส่ง Bearer token)
    GET    /api/admin/users    รายชื่อผู้ใช้ทั้งหมด (admin เท่านั้น — ใช้ทดสอบ role check)
    GET    /api/menu/popular   เมนูยอดนิยม (จัดอันดับจากยอดถูกใจ)
    GET    /api/favorites      รายการเมนูโปรดของผู้ใช้ปัจจุบัน (ต้องล็อกอิน)
    POST   /api/favorites      กดถูกใจเมนู (ต้องล็อกอิน)
    DELETE /api/favorites/{mid} ยกเลิกถูกใจเมนู (ต้องล็อกอิน)
    GET    /api/menu/{mid}     ดูรายละเอียดเมนูเดียว (public)
    GET    /api/menu/{mid}/reviews  ดูรีวิว+คะแนนเฉลี่ยของเมนู (public)
    POST   /api/reviews        ให้ดาว+คอมเมนต์เมนู (ต้องล็อกอิน)
    POST   /api/admin/backfill-images  ดึงรูปจริงจาก Pexels เติมเมนูที่ยังไม่มีรูป (admin)

รันด้วย:
    uvicorn api_server:app --reload --host 0.0.0.0 --port 8000
   
 set RECIPE_GOOGLE_CLIENT_ID=1004629703821-s26ndmkuj0ta5uq4quin0lraho6bfb5h.apps.googleusercontent.com
    

ทดสอบด้วยเบราว์เซอร์ที่ http://127.0.0.1:8000/docs
"""
import logging

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field

# โหลดค่าจากไฟล์ .env ก่อน import โมดูลที่ต้องใช้ Environment Variable
load_dotenv()

import auth
import menu_repository
import service

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Recipe Recommendation API",
    description="API แนะนำสูตรอาหารไทยด้วย AI (KNN) — เชื่อมต่อกับแอพ Flutter",
    version="1.0.0",
)

# CORS: เปิดกว้างไว้ก่อนสำหรับตอนพัฒนา (แอพมือถือ/เว็บทดสอบเรียกได้จากทุกที่)
# ก่อนขึ้น production ควรจำกัด allow_origins ให้เหลือเฉพาะโดเมน/แอพจริงของทีม
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def _warm_up_engine() -> None:
    """โหลด/เทรนโมเดลตอนเซิร์ฟเวอร์เริ่มทำงาน (ครั้งเดียว) แทนที่จะรอให้ request
    แรกมาถึงค่อยโหลด — กัน request แรกของผู้ใช้จริงต้องรอนาน
    """
    logger.info("Warming up recommendation engine...")
    engine = service.get_engine()
    logger.info("Engine ready — %d menus loaded", engine.menu_count)


# ---------------------------------------------------------------------------
# Response / request schemas
# ---------------------------------------------------------------------------


class MenuResult(BaseModel):
    mid: int | None = None  # ใช้เปิดหน้ารายละเอียดเมนู/รีวิวต่อ — None ถ้าหาไม่เจอใน DB (ไม่ควรเกิดขึ้นจริงเพราะ sync ไว้แล้ว)
    menu: str
    score: float
    ingredients: list[str]
    method: str


class SearchResponse(BaseModel):
    query: str
    count: int
    results: list[MenuResult]


class RecommendRequest(BaseModel):
    ingredients: str = Field(
        ..., description="รายการวัตถุดิบ คั่นด้วยช่องว่างหรือจุลภาค เช่น 'กุ้งสด ข่า ตะไคร้'"
    )
    top_k: int = Field(3, ge=1, le=20, description="จำนวนเมนูที่ต้องการให้แนะนำ")


class HealthResponse(BaseModel):
    status: str
    menus_loaded: int


# --- Auth schemas (STEP 4-7) ---


class RegisterRequest(BaseModel):
    email: str
    fullname: str
    password: str = Field(..., min_length=8)
    tel: str | None = None


class LoginRequest(BaseModel):
    email: str
    password: str


class GoogleLoginRequest(BaseModel):
    id_token: str = Field(..., description="ID Token ที่ได้จาก google_sign_in ฝั่ง Flutter")


class UpdateProfileRequest(BaseModel):
    fullname: str | None = None
    tel: str | None = None
    password: str | None = Field(None, min_length=8, description="ใส่เฉพาะตอนต้องการเปลี่ยนรหัสผ่าน")


class UserResponse(BaseModel):
    uid: int
    email: str
    fullname: str
    tel: str | None
    role: int  # 0 = admin, 1 = member


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


class MenuFavoriteItem(BaseModel):
    mid: int
    menu_name: str
    image: str | None
    ingredient: str
    method: str
    # มีค่าจริงเฉพาะตอนมาจาก /api/menu/popular (คำนวณดาวเฉลี่ยไว้ให้แล้ว) —
    # endpoint อื่น (favorites, menu/{mid}) ยังไม่ได้คำนวณให้ จึงเป็น None/0
    # ไปก่อน (ไม่ error แค่ยังไม่มีข้อมูลให้แสดง)
    average_score: float | None = None
    review_count: int = 0


class FavoriteListResponse(BaseModel):
    count: int
    results: list[MenuFavoriteItem]


class AddFavoriteRequest(BaseModel):
    mid: int


class ReviewRequest(BaseModel):
    mid: int
    score: int = Field(..., ge=1, le=5)
    comment: str | None = None


class ReviewItem(BaseModel):
    uid: int
    fullname: str
    score: int
    comment: str | None
    review_date: str


class ReviewListResponse(BaseModel):
    average_score: float | None
    review_count: int
    reviews: list[ReviewItem]


# ---------------------------------------------------------------------------
# Auth dependency — ดึง Bearer token จาก header, แปลงเป็น User, เช็คสิทธิ์
# ---------------------------------------------------------------------------

_bearer_scheme = HTTPBearer(description="ใส่ JWT ที่ได้จาก /api/auth/login หรือ /api/auth/google")


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(_bearer_scheme),
) -> auth.User:
    try:
        return auth.get_current_user(credentials.credentials)
    except auth.AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc


def require_admin(current_user: auth.User = Depends(get_current_user)) -> auth.User:
    """Dependency สำหรับ endpoint ที่ Admin เท่านั้นเข้าได้ — Member เรียกแล้วได้ 403
    (ตาม STEP 5 ข้อ "ต้องไม่ให้ Member สามารถเข้าถึง API ของ Admin ได้")
    """
    if not current_user.is_admin:
        raise HTTPException(status_code=403, detail="ต้องเป็นแอดมินเท่านั้น")
    return current_user


def _user_to_response(user: auth.User) -> UserResponse:
    return UserResponse(
        uid=user.uid, email=user.email, fullname=user.fullname, tel=user.tel, role=user.role
    )


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    engine = service.get_engine()
    return HealthResponse(status="ok", menus_loaded=engine.menu_count)


def _attach_mid(results: list[dict]) -> list[dict]:
    """เติม `mid` ให้แต่ละผลลัพธ์ค้นหา โดยเทียบชื่อเมนูกับตาราง Menu ใน DB
    (เมนูจากโมเดล KNN ถูก sync เข้า DB ด้วยชื่อเดียวกันไว้แล้วตอน startup)
    ใช้เปิดหน้ารายละเอียดเมนู/ให้รีวิวต่อจากผลค้นหาได้
    """
    enriched = []
    for r in results:
        menu_row = menu_repository.get_menu_by_name(r["menu"])
        enriched.append({**r, "mid": menu_row.mid if menu_row else None})
    return enriched


@app.get("/api/search", response_model=SearchResponse)
def search_auto(
    q: str = Query(..., min_length=1, description="คำค้นหา: ชื่อเมนูหรือวัตถุดิบก็ได้"),
    top_k: int = Query(3, ge=1, le=20),
) -> SearchResponse:
    """ค้นหาแบบอัตโนมัติ ใช้กับช่องค้นหาช่องเดียวในหน้าแอพ (เหมือนหน้าค้นหาในเอกสารโครงงาน)"""
    results = _attach_mid(service.search_auto(q, top_k=top_k))
    return SearchResponse(query=q, count=len(results), results=results)


@app.get("/api/search/name", response_model=SearchResponse)
def search_by_name_endpoint(
    name: str = Query(..., min_length=1, description="ชื่อเมนู (พิมพ์ไม่ครบก็ค้นเจอได้)"),
    top_k: int = Query(3, ge=1, le=20),
) -> SearchResponse:
    """ค้นหาเฉพาะด้วยชื่อเมนู — ตรงกับ /api/search/name (GET) ในเอกสารโครงงาน"""
    results = _attach_mid(service.search_name(name, top_k=top_k))
    return SearchResponse(query=name, count=len(results), results=results)


@app.post("/api/recommend", response_model=SearchResponse)
def recommend_endpoint(body: RecommendRequest) -> SearchResponse:
    """แนะนำเมนูจากวัตถุดิบที่มี — ตรงกับ /api/recommend (POST) ในเอกสารโครงงาน"""
    results = service.search_ingredients(body.ingredients, top_k=body.top_k)
    if not results:
        # ไม่ error 404/500 — คืน 200 พร้อมลิสต์ว่าง ให้แอพแสดง "ไม่พบเมนูที่เกี่ยวข้อง"
        # ได้ตรงๆ โดยไม่ต้อง handle exception เพิ่ม (ค้นหาไม่เจอไม่ใช่ความผิดพลาดของระบบ)
        return SearchResponse(query=body.ingredients, count=0, results=[])
    results = _attach_mid(results)
    return SearchResponse(query=body.ingredients, count=len(results), results=results)


@app.post("/api/auth/register", response_model=TokenResponse)
def register_endpoint(body: RegisterRequest) -> TokenResponse:
    """STEP 4 — สมัครสมาชิกด้วย Email + Password คืน JWT กลับไปทันที (ไม่ต้อง
    ล็อกอินซ้ำหลังสมัคร — สะดวกกว่าฝั่งแอพ)
    """
    try:
        user = auth.register_user(
            email=body.email, fullname=body.fullname, password=body.password, tel=body.tel
        )
    except auth.AuthError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    token = auth.create_access_token(user)
    return TokenResponse(access_token=token, user=_user_to_response(user))


@app.post("/api/auth/login", response_model=TokenResponse)
def login_endpoint(body: LoginRequest) -> TokenResponse:
    """STEP 5 — ล็อกอินด้วย Email + Password คืน JWT"""
    try:
        user = auth.authenticate(body.email, body.password)
    except auth.AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc

    token = auth.create_access_token(user)
    return TokenResponse(access_token=token, user=_user_to_response(user))


@app.post("/api/auth/google", response_model=TokenResponse)
def google_login_endpoint(body: GoogleLoginRequest) -> TokenResponse:
    """STEP 6 — ล็อกอิน/สมัครสมาชิกผ่าน Google OAuth คืน JWT"""
    try:
        user = auth.authenticate_google(body.id_token)
    except auth.AuthError as exc:
        raise HTTPException(status_code=401, detail=str(exc)) from exc

    token = auth.create_access_token(user)
    return TokenResponse(access_token=token, user=_user_to_response(user))


@app.post("/api/auth/logout")
def logout_endpoint(current_user: auth.User = Depends(get_current_user)) -> dict:
    """JWT เป็น stateless — เซิร์ฟเวอร์ไม่มี session ให้ลบ การ 'logout' จริงๆ
    คือฝั่ง Flutter ลบ token ที่เก็บไว้ในเครื่องทิ้ง endpoint นี้มีไว้ให้เรียก
    เพื่อความสมบูรณ์ของ flow เท่านั้น (เผื่ออนาคตอยากทำ token blacklist เพิ่ม)
    """
    return {"message": "logged out"}


@app.get("/api/auth/me", response_model=UserResponse)
def get_me_endpoint(current_user: auth.User = Depends(get_current_user)) -> UserResponse:
    return _user_to_response(current_user)


@app.put("/api/auth/me", response_model=UserResponse)
def update_me_endpoint(
    body: UpdateProfileRequest, current_user: auth.User = Depends(get_current_user)
) -> UserResponse:
    """แก้ไขข้อมูลส่วนตัว (STEP 7): ชื่อ-นามสกุล, เบอร์โทรศัพท์, รหัสผ่าน
    (ตามขอบเขตงานข้อ 2.2 ในเอกสาร) — ส่งเฉพาะฟิลด์ที่ต้องการเปลี่ยนมาก็พอ
    """
    fields, params = [], []
    if body.fullname is not None:
        fields.append("Fullname = ?")
        params.append(body.fullname.strip())
    if body.tel is not None:
        fields.append("Tel = ?")
        params.append(body.tel)
    if body.password is not None:
        fields.append("Password = ?")
        params.append(auth.hash_password(body.password))

    if fields:
        from database import db_session

        with db_session() as conn:
            conn.execute(
                f"UPDATE User SET {', '.join(fields)} WHERE UID = ?",
                (*params, current_user.uid),
            )

    updated = auth.get_user_by_id(current_user.uid)
    return _user_to_response(updated)  # type: ignore[arg-type]


@app.get("/api/admin/users", response_model=list[UserResponse])
def list_users_endpoint(_admin: auth.User = Depends(require_admin)) -> list[UserResponse]:
    """Admin เท่านั้น — ใช้ทดสอบว่า Member เรียกแล้วโดนบล็อกจริง (Test 6)"""
    from database import db_session

    with db_session() as conn:
        rows = conn.execute("SELECT * FROM User").fetchall()
    return [
        UserResponse(uid=r["UID"], email=r["Email"], fullname=r["Fullname"], tel=r["Tel"], role=r["role"])
        for r in rows
    ]


@app.get("/api/menu/popular", response_model=FavoriteListResponse)
def popular_menu_endpoint(limit: int = Query(10, ge=1, le=50)) -> FavoriteListResponse:
    """เมนูยอดนิยม จัดอันดับจากยอดถูกใจ + คะแนนดาวเฉลี่ย (ดูสูตรใน
    menu_repository.list_popular_menus) — public ไม่ต้องล็อกอิน
    """
    menus = menu_repository.list_popular_menus(limit=limit)
    return FavoriteListResponse(
        count=len(menus),
        results=[
            MenuFavoriteItem(
                mid=m.mid,
                menu_name=m.menu_name,
                image=m.image,
                ingredient=m.ingredient,
                method=m.method,
                average_score=m.average_score,
                review_count=m.review_count,
            )
            for m in menus
        ],
    )


# หมายเหตุ: /api/menu/popular (fixed path) ต้องประกาศไว้ "ก่อน" /api/menu/{mid}
# (parameterized path) เสมอ — FastAPI จับคู่ route ตามลำดับที่ประกาศ ถ้าสลับ
# กัน คำว่า "popular" จะถูกพยายามแปลงเป็น int (mid) แล้วพัง 422 แทน


@app.get("/api/menu/{mid}", response_model=MenuFavoriteItem)
def get_menu_detail_endpoint(mid: int) -> MenuFavoriteItem:
    """ดูรายละเอียดเมนูเดียวแบบเต็ม (ใช้กับหน้ารายละเอียดเมนูในแอพ) — public"""
    menu = menu_repository.get_menu_by_id(mid)
    if menu is None:
        raise HTTPException(status_code=404, detail="ไม่พบเมนูนี้")
    return MenuFavoriteItem(
        mid=menu.mid, menu_name=menu.menu_name, image=menu.image, ingredient=menu.ingredient, method=menu.method
    )


@app.get("/api/menu/{mid}/reviews", response_model=ReviewListResponse)
def list_reviews_endpoint(mid: int) -> ReviewListResponse:
    """รายการรีวิว + คะแนนเฉลี่ยของเมนูนี้ — public ไม่ต้องล็อกอินก็ดูได้"""
    if menu_repository.get_menu_by_id(mid) is None:
        raise HTTPException(status_code=404, detail="ไม่พบเมนูนี้")
    summary = menu_repository.get_menu_review_summary(mid)
    reviews = menu_repository.list_reviews(mid)
    return ReviewListResponse(
        average_score=summary["average_score"],
        review_count=summary["review_count"],
        reviews=[ReviewItem(**r) for r in reviews],
    )


@app.post("/api/reviews")
def submit_review_endpoint(
    body: ReviewRequest, current_user: auth.User = Depends(get_current_user)
) -> dict:
    """ให้ดาว + คอมเมนต์เมนู (ต้องล็อกอิน) — รีวิวซ้ำเมนูเดิมจะ 'แก้ไข' ของเดิม
    แทนสร้างใหม่ (ดู menu_repository.upsert_review และ UNIQUE(UID, MID))
    """
    if menu_repository.get_menu_by_id(body.mid) is None:
        raise HTTPException(status_code=404, detail="ไม่พบเมนูนี้")
    menu_repository.upsert_review(current_user.uid, body.mid, body.score, body.comment)
    return {"message": "saved"}


@app.post("/api/admin/backfill-images")
def backfill_images_endpoint(
    limit: int = Query(50, ge=1, le=200),
    _admin: auth.User = Depends(require_admin),
) -> dict:
    """Admin เท่านั้น — สั่งดึงรูปจริงจาก Pexels มาใส่เมนูที่ยังไม่มีรูป ต้องตั้ง
    env var `PEXELS_API_KEY` ไว้ก่อน ไม่งั้นจะอัปเดตได้ 0 เมนู
    """
    updated = menu_repository.backfill_missing_images(limit=limit)
    return {"updated": updated, "message": f"ดึงรูปสำเร็จ {updated} เมนู"}


@app.get("/api/favorites", response_model=FavoriteListResponse)
def list_favorites_endpoint(current_user: auth.User = Depends(get_current_user)) -> FavoriteListResponse:
    menus = menu_repository.list_favorites(current_user.uid)
    return FavoriteListResponse(
        count=len(menus),
        results=[
            MenuFavoriteItem(mid=m.mid, menu_name=m.menu_name, image=m.image, ingredient=m.ingredient, method=m.method)
            for m in menus
        ],
    )


@app.post("/api/favorites")
def add_favorite_endpoint(
    body: AddFavoriteRequest, current_user: auth.User = Depends(get_current_user)
) -> dict:
    if menu_repository.get_menu_by_id(body.mid) is None:
        raise HTTPException(status_code=404, detail="ไม่พบเมนูนี้")
    menu_repository.add_favorite(current_user.uid, body.mid)
    return {"message": "added"}


@app.delete("/api/favorites/{mid}")
def remove_favorite_endpoint(mid: int, current_user: auth.User = Depends(get_current_user)) -> dict:
    menu_repository.remove_favorite(current_user.uid, mid)
    return {"message": "removed"}


@app.exception_handler(RuntimeError)
def runtime_error_handler(request, exc: RuntimeError):  # noqa: ANN001 - FastAPI signature
    # เช่นกรณี dataset โหลดไม่สำเร็จตอน startup
    logger.exception("Unhandled RuntimeError")
    raise HTTPException(status_code=503, detail=str(exc))
