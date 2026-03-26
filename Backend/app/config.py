from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    supabase_url: str
    supabase_service_role_key: str
    supabase_anon_key: str

    groq_api_key: str
    groq_model: str = "llama-3.3-70b-versatile"

    qdrant_url: str
    qdrant_api_key: str
    qdrant_collection: str = "medical_rag"

    jwt_secret_key: str
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 10080  # 7 days

    app_name: str = "Aarogyan"
    app_env: str = "development"
    cors_origins: str = "http://localhost,http://localhost:3000,http://10.0.2.2"

    model_config = SettingsConfigDict(env_file=".env", case_sensitive=False)

    @property
    def cors_origins_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",")]


@lru_cache()
def get_settings() -> Settings:
    return Settings()
