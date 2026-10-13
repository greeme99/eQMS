from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Application
    PROJECT_NAME: str = "eQMS Backend Core"
    VERSION: str = "0.1.0"
    ENVIRONMENT: str = "development"
    DEBUG: bool = True
    API_V1_STR: str = "/api/v1"
    SECRET_KEY: str = "eqms-development-secret-key-32chars-minimum!!"

    # Database (PostgreSQL)
    DATABASE_URL: str = "postgresql+asyncpg://eqms_user:eqms_dev_password@localhost:5432/eqms"

    # Storage (MinIO)
    MINIO_ENDPOINT: str = "localhost:9000"
    MINIO_ROOT_USER: str = "minioadmin"
    MINIO_ROOT_PASSWORD: str = "minioadmin123"
    MINIO_DEFAULT_BUCKET: str = "eqms-documents"
    MINIO_SECURE: bool = False

    # External Integration
    DSS_BASE_URL: str = "http://localhost:8080/services/rest"
    QDRANT_HOST: str = "localhost"
    QDRANT_PORT: int = 6333


settings = Settings()
