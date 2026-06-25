FROM python:3.12-slim

WORKDIR /app

ENV PIP_DEFAULT_TIMEOUT=120 PIP_RETRIES=5

RUN useradd --create-home --uid 10001 appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

USER appuser

ENV APP_PORT=8000

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${APP_PORT:-8000}"]
