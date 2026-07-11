import logging
import logging.config

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app.api.tune import router as tune_router
from app.config import settings

logging.basicConfig(
    level=logging.DEBUG if settings.is_development else logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="TUNAI Cloud AI Orchestrator",
    version="0.1.0",
    docs_url="/docs" if settings.is_development else None,
    redoc_url=None,
)

# CORS — conservative: allow only explicitly configured origins
_origins = settings.cors_origins
if not _origins and settings.is_development:
    _origins = ["http://localhost", "http://127.0.0.1"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type"],
)

app.include_router(tune_router, prefix="/v1/tune")


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "service": "tunai-cloud", "version": "0.1.0"}


@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.error("unhandled_error path=%s error=%s", request.url.path, type(exc).__name__)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"},
    )
