from app.orchestrator.schemas import InterpretRequest, InterpretResponse
from app.providers.base import AIProvider, ProviderNotConfiguredError


class ClaudeProvider(AIProvider):
    """Placeholder — not yet implemented. Raises ProviderNotConfiguredError on use."""

    async def interpret(self, request: InterpretRequest) -> InterpretResponse:
        raise ProviderNotConfiguredError(
            "Claude provider is not yet implemented. "
            "Set AI_PROVIDER=gemini or implement this provider."
        )
