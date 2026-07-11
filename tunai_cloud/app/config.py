from typing import Literal
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    APP_ENV: Literal["development", "production"] = "development"
    APP_HOST: str = "127.0.0.1"
    APP_PORT: int = 8100

    AI_PROVIDER: Literal["gemini", "openai", "claude"] = "gemini"

    GEMINI_API_KEY: str = ""
    GEMINI_MODEL: str = "gemini-2.5-flash"

    OPENAI_API_KEY: str = ""
    ANTHROPIC_API_KEY: str = ""

    CORS_ALLOWED_ORIGINS: str = ""
    REQUEST_TIMEOUT_SECONDS: int = 20
    MAX_USER_TEXT_LENGTH: int = 1000

    @property
    def cors_origins(self) -> list[str]:
        if not self.CORS_ALLOWED_ORIGINS.strip():
            return []
        return [o.strip() for o in self.CORS_ALLOWED_ORIGINS.split(",") if o.strip()]

    @property
    def is_development(self) -> bool:
        return self.APP_ENV == "development"


settings = Settings()
