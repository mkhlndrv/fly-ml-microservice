# Root Dockerfile, used by `fly deploy` to build the public API container.
#
# Fly Compose (build.compose in fly.toml) needs the buildable service to use the
# repo root as its build context, so the API image is built from here. The local
# docker-compose.local.yml builds the same code from ./api_service instead.
FROM python:3.12-slim

WORKDIR /app

RUN useradd --create-home --uid 10001 appuser

COPY api_service/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api_service/main.py .

USER appuser

ENV APP_PORT=8000

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${APP_PORT:-8000}"]
