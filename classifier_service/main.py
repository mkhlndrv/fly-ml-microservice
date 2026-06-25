"""Internal classifier service.

Not exposed to the internet. The orchestrator calls POST /score with a piece of
text and gets back a human-or-bot judgement. The model is rule-based on purpose:
the assignment is about the deployment topology, not model quality, and a tiny
dependency-free classifier keeps the sidecar image small and the cold start fast.
"""
from __future__ import annotations

import os
import re
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field


class ScoreRequest(BaseModel):
    text: str = Field(min_length=1, max_length=5000)


class ScoreResponse(BaseModel):
    label: str                                  # "bot" or "human"
    proba: float = Field(ge=0.0, le=1.0)        # == is_bot_probability (kept for parity)
    is_bot_probability: float = Field(ge=0.0, le=1.0)
    model_name: str
    model_version: str


class HumanOrBotClassifier:
    """Cheap heuristic 'human or bot' scorer.

    It leans on a handful of signals that tend to separate canned assistant
    replies from how people actually type in a chat. Everything is clamped to
    [0, 1] so the output is always a valid probability.
    """

    # Phrases that scream "language model assistant".
    bot_phrases = (
        "as an ai", "language model", "i am an ai", "i'm an ai", "as a bot",
        "happy to help", "how can i assist", "i can help you", "let me know if",
        "certainly!", "furthermore", "in conclusion", "great question",
    )
    # Very polite/formal connective words that bots overuse.
    bot_words = ("assist", "additionally", "however", "moreover", "therefore", "utilize")
    # Casual, messy, human-looking signals.
    human_words = ("lol", "haha", "idk", "btw", "yeah", "nah", "omg", "u", "ur", "gonna")

    def predict(self, text: str) -> tuple[str, float]:
        normalized = text.lower().strip()
        if not normalized:
            return "human", 0.5

        score = 0.18  # slight prior toward "human"

        score += 0.28 * sum(phrase in normalized for phrase in self.bot_phrases)
        score += 0.08 * sum(re.search(rf"\b{w}\b", normalized) is not None for w in self.bot_words)
        score -= 0.12 * sum(re.search(rf"\b{w}\b", normalized) is not None for w in self.human_words)

        # Long, tidy, well-punctuated messages read more like generated text.
        if len(normalized) > 280:
            score += 0.12
        if normalized.count("\n") >= 2 or " - " in normalized or "1." in normalized:
            score += 0.1  # lists / markdown-ish structure
        # Emoji or repeated punctuation ("!!!", "??") look human.
        if re.search(r"[\U0001F300-\U0001FAFF]", text) or re.search(r"[!?]{2,}", text):
            score -= 0.12

        probability = max(0.01, min(score, 0.99))
        label = "bot" if probability >= 0.5 else "human"
        return label, round(probability, 4)


SCORES = Counter("classifier_score_requests_total", "Total classifier score requests")
LATENCY = Histogram("classifier_score_latency_seconds", "Classifier score latency")


@asynccontextmanager
async def lifespan(app_: FastAPI):
    app_.state.model = HumanOrBotClassifier()
    app_.state.model_name = os.getenv("MODEL_NAME", "human-or-bot-rules")
    app_.state.model_version = os.getenv("MODEL_VERSION", "sidecar-v1")
    yield
    app_.state.model = None


app = FastAPI(title="Classifier sidecar (human or bot)", version="1.0.0", lifespan=lifespan)


@app.get("/health", tags=["system"])
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready", tags=["system"])
def ready() -> dict[str, Any]:
    return {
        "status": "ready",
        "model_name": app.state.model_name,
        "model_version": app.state.model_version,
    }


@app.post("/score", response_model=ScoreResponse, tags=["inference"])
def score(request: ScoreRequest) -> ScoreResponse:
    started = time.perf_counter()
    label, probability = app.state.model.predict(request.text)
    SCORES.inc()
    LATENCY.observe(time.perf_counter() - started)
    return ScoreResponse(
        label=label,
        proba=probability,
        is_bot_probability=probability,
        model_name=app.state.model_name,
        model_version=app.state.model_version,
    )


@app.get("/metrics", tags=["system"])
def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
