from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.config import get_settings
from app.routers import auth, profile, consultations, sessions, assistant, documents, buddy, mental_health, export

settings = get_settings()

app = FastAPI(
    title="Aarogyan API",
    description="Backend for the Aarogyan health companion app",
    version="1.0.0",
    docs_url="/docs" if settings.app_env == "development" else None,
    redoc_url="/redoc" if settings.app_env == "development" else None,
)

# CORS — allow Flutter app (local dev + Android emulator)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Register routers
app.include_router(auth.router, prefix="/api/v1")
app.include_router(profile.router, prefix="/api/v1")
app.include_router(consultations.router, prefix="/api/v1")
app.include_router(sessions.router, prefix="/api/v1")
app.include_router(assistant.router, prefix="/api/v1")
app.include_router(documents.router, prefix="/api/v1")
app.include_router(buddy.router, prefix="/api/v1")
app.include_router(mental_health.router, prefix="/api/v1")
app.include_router(export.router, prefix="/api/v1")


@app.get("/")
async def root():
    return {"status": "ok", "app": settings.app_name}


@app.get("/health")
async def health():
    return {"status": "healthy"}
