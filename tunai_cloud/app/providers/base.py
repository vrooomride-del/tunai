from abc import ABC, abstractmethod

from app.orchestrator.schemas import InterpretRequest, InterpretResponse


class AIProvider(ABC):
    @abstractmethod
    async def interpret(self, request: InterpretRequest) -> InterpretResponse:
        ...


class ProviderNotConfiguredError(Exception):
    """Raised when a provider is selected but not configured for this environment."""
