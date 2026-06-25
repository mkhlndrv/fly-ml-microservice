# Fly ML microservice (human-or-bot)

A small production-style ML system deployed as a multi-container app on Fly.io.
Three containers run in one Fly Machine; only the public API faces the internet.

```
client ──POST /predict──► api / orchestrator  (public, :8000)
                              │  calls /score
                              ▼
                          classifier sidecar   (internal, localhost:8001)
                              │  stores result
                              ▼
                          postgres sidecar     (internal, localhost:5432)
```

- **api / orchestrator** — the only internet-facing service. `POST /predict`
  takes user text, calls the classifier, stores the request + result in Postgres,
  and returns the prediction. Also serves `/health`, `/ready`, `/metrics` and
  `/predictions/recent`.
- **classifier** — internal service. `POST /score` returns a human-or-bot
  judgement. Rule-based and dependency-free, so the sidecar image is tiny.
- **postgres** — internal database. Stores every prediction.

On Fly the three containers share one network namespace, so the API reaches the
sidecars over `localhost`. Locally (Docker Compose) it reaches them by service
name. Both come from env vars (`CLASSIFIER_URL`, `DATABASE_URL`), so the same
code runs in both places. The containers use `APP_PORT`, because Fly reserves
`PORT` for the public service.

## Run locally

```bash
./scripts/00_run_local.sh
# API:        http://127.0.0.1:8013/docs
# classifier: http://127.0.0.1:8014/docs
# postgres:   127.0.0.1:5434
docker compose -f docker-compose.local.yml down   # stop
```

`00_run_local.sh` builds the stack and runs the smoke test (`/health`, `/ready`,
two `/predict` calls, and `/predictions/recent` to show the results were stored).

## Endpoints

| Method | Path                   | What it does                                   |
| ------ | ---------------------- | ---------------------------------------------- |
| POST   | `/predict`             | Classify text, store the result, return it     |
| GET    | `/health`              | Liveness (process is up)                       |
| GET    | `/ready`               | Readiness (classifier **and** database reachable) |
| GET    | `/predictions/recent`  | Most recent stored predictions (DB proof)      |
| GET    | `/metrics`             | Prometheus metrics                             |

`POST /predict` needs only `text`:

```bash
curl -X POST http://127.0.0.1:8013/predict \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello"}'
```

```json
{
  "id": "…",
  "label": "human",
  "proba": 0.18,
  "is_bot_probability": 0.18,
  "model_name": "human-or-bot-rules",
  "model_version": "local-sidecar-v1",
  "latency_ms": 4.1
}
```

## Deploy to Fly.io

You need the Fly CLI (`https://fly.io/docs/flyctl/install/`), to be logged in
(`fly auth login`), and the app names your instructor assigned you.

```bash
# 1. set your names (or copy .env.example to .env and edit it)
export FLY_ORG=harbour-ml-solution-course
export FLY_REGION=fra
export COMPOSE_APP=<your-compose-app>
export IMAGES_APP=<your-images-app>

# 2. build + push the internal classifier image to the Fly registry
./scripts/01_build_push_images.sh

# 3. deploy the 3-container Machine (set DRY_RUN=1 to validate only)
./scripts/02_deploy_fly.sh

# 4. smoke-test the public URL
./scripts/03_test.sh https://$COMPOSE_APP.fly.dev
```

Manual check:

```bash
curl -X POST https://$COMPOSE_APP.fly.dev/predict \
  -H "Content-Type: application/json" -d '{"text":"Hello"}'
curl https://$COMPOSE_APP.fly.dev/health
curl https://$COMPOSE_APP.fly.dev/ready
```

`02_deploy_fly.sh` fills `fly.toml.template` / `docker-compose.fly.yml.template`
into `fly.generated.toml` / `docker-compose.fly.yml` (both gitignored), so
per-student app names are never committed.

## Register on youare.bot

After deploying, register the public URL at <https://youare.bot>:

```
https://<your-compose-app>.fly.dev
```

## Notes

- The Postgres sidecar is fine for this deployment demo. For anything real, use a
  Fly volume or managed Postgres so data survives a Machine restart.
- No secrets are committed. The local Postgres password (`app`) is a throwaway
  demo credential.
- Starting point: the `fly_compose_microservices` example from the Session 13
  materials, adapted here into a standalone repo with a human-or-bot classifier.
