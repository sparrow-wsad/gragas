# ADR 0004: One application in one container, queue in Postgres

- **Status:** accepted
- **Date:** 2026-09-19
- **Depends on:** [ADR 0003](0003-pgvector-instead-of-onyx.md)

## Context

The original plan assumed four independently running pieces: the capture API, Redis as a queue, a worker on RQ or Celery, and the Teams bot. The split followed convention rather than any requirement — no load analysis accompanied it.

The scale is small: around ten people and on the order of five hundred events per day. Processing is asynchronous and nobody waits on its result in real time.

Azure Container Apps bills per replica. The monthly free grant covers roughly 200 hours of a 0.25 vCPU replica. One replica running continuously costs about 14 USD per month beyond that grant — three of them triple it. Redis as a separate service adds another fixed line.

After ADR 0003 all system state already lives in a single Postgres that holds facts, history and vectors.

## Decision

**One container.** The application contains the HTTP API (candidate intake, review, search, MCP server, bot endpoint) and the worker running as a background task in the same process.

**Queue in Postgres.** Handled by the **Procrastinate** library, which uses `LISTEN/NOTIFY` and row locking that skips locked rows. The library requires no Postgres extensions, so the Azure extension allowlist does not apply to it. Redis does not appear in the architecture.

## Consequences

**Positive:**
- Compute cost drops to one replica; with scale-to-zero it fits inside the free grant.
- Azure Cache for Redis disappears from the service list.
- One image, one deployment pipeline, one set of secrets.
- The local environment is the application and a database, with no queue broker.
- A job is enqueued in the same transaction as the data, so queue state and data state cannot diverge.
- Retries with backoff, periodic jobs and immediate dispatch come from the library rather than our own code.

**Negative, and accepted:**
- The API and the worker share resources. A long model call can affect API response time; asynchronous processing and low volume mitigate this.
- No independent scaling of the two parts.
- Scale-to-zero means cold starts. This does not matter for background writes, but **the Teams bot has a limited response window** — a cold start plus a model call may not fit inside it. To be verified by measurement; if needed, keep a minimum replica during working hours.

**When to revisit:** when API response time starts to visibly depend on worker activity, or when the queue stops draining. Splitting into two services is then a deployment configuration change, provided the boundary between API and worker stays explicit in the code.

## Alternatives considered

- **Three separate Container Apps (original plan)** — rejected; cost disproportionate to scale.
- **Container Apps Jobs for the worker** — reasonable for batch processing, but adds a second image and separate configuration for little gain.
- **Azure Cache for Redis** — deferred; it returns when the database-backed queue runs out of throughput.
- **Azure Storage Queue** — the cheapest queue service, with a native KEDA scaler, but it introduces a dual write: the event goes to the database and the message separately to the queue, so a failure of either leaves the two states inconsistent. Scaling is not the deciding factor, since KEDA also has a PostgreSQL scaler.
- **Azure Service Bus** — dead-lettering, FIFO and sessions are not needed here.
- **PgQueuer** — the same idea as Procrastinate, faster and with fewer features; the performance difference is irrelevant at our volume.
