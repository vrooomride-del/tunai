import logging

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from app.orchestrator.schemas import InterpretRequest, InterpretResponse
from app.orchestrator.service import AIOrchestratorService

router = APIRouter()
logger = logging.getLogger(__name__)

_service = AIOrchestratorService()


@router.post("/interpret", response_model=InterpretResponse)
async def interpret(request: InterpretRequest) -> InterpretResponse:
    return await _service.interpret(request)
