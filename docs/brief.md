# Brief: a company memory of project facts

The concept in one place, kept current with the decisions in `adrs/`. Where this brief and an ADR disagree, the ADR wins.

| ADR | Decision |
|---|---|
| [0001](adrs/0001-single-instance-no-tenant-isolation.md) | Single instance, tenant isolation is not a security boundary |
| [0002](adrs/0002-postgres-as-source-of-truth.md) | Postgres is the source of truth, no GitHub facts repository |
| [0003](adrs/0003-pgvector-instead-of-onyx.md) | Search on pgvector in Azure Postgres, no Onyx |
| [0004](adrs/0004-single-container-postgres-queue.md) | One application in one container, queue in Postgres |
| [0005](adrs/0005-client-side-extraction.md) | The coding session writes the fact, transcripts stay local |

## The problem

A software house of about ten people runs three technically similar projects for different clients. The differences live in **business rules**, and those rules live in senior developers' heads, in chat threads and in pull request descriptions. The result: slow onboarding, the same "how does this work?" questions over and over, and bugs caused by not knowing a rule. The code does not say it — code shows *how*, not *why*.

## The idea in one sentence

Capture domain facts *during normal work*, put them through a human, store them in Postgres, and serve them from the same database to agents (over MCP) and to people (a Teams bot).

A **fact** is one sentence about system behaviour plus **why**, a source and an owner, written in English. For example: a user without the `admin` role does not see the `organizations` filter on the `fleets` table, because the filter reveals the client's list of organisations — a product decision from PR #412.

## How search works

The whole layer sits in Azure Database for PostgreSQL. The `vector` extension adds a column type and distance operators — it is not a separate service or a separate system.

Retrieval is **hybrid**: vector search captures the meaning of a question, full-text search catches literal table, role and field names. Reciprocal Rank Fusion merges the two result lists. Facts in English let us use the built-in full-text configuration with stemming, without workarounds.

Embeddings live in their own table keyed by fact and model. Changing models therefore means computing a new set alongside the old one and switching after comparing results, rather than migrating blind.

## How it fits together

1. **Write** — the `/fact` command inside a coding session. The agent composes a fact sentence with its rationale and source using the full conversation context; without arguments it proposes one to three facts to confirm on the spot. A finished candidate goes to the server, not a transcript.
2. **Process** — the worker checks whether a similar fact already exists (deduplication) and routes the candidate to review. Candidates marked as engineering conventions become proposals for `.claude/rules/`.
3. **Review** — a human in the loop, always. A minimal candidate list first, Teams cards later (approve / reject / it's a convention / edit). Human decisions double as a labelled set for improving classification.
4. **Read** — on approval the embedding is computed and the fact becomes searchable immediately. The agent queries over MCP mid-task; people ask the Teams bot. Every answer cites a fact `id`; no match means "I don't have that recorded" plus a suggestion to run `/fact`.

## Where facts live

| Where | What | Role |
|---|---|---|
| `facts` + `fact_versions` | candidates and facts — **the same record, different status** — plus change history | **source of truth** |
| `fact_embeddings` | vectors, keyed by fact and model | search layer |

One database. No cross-system synchronisation and no publishing delay.

## Building blocks

**Built by us**

| Block | Responsibility | Where |
|---|---|---|
| `company-memory` plugin | `/fact` command, MCP client | developer machines |
| Memory App | one container: candidate intake, deduplication, review, search, MCP server, bot endpoint | Container Apps, one replica |

**Azure services**

| Block | Responsibility | Note |
|---|---|---|
| PostgreSQL + `vector` | facts, history, vectors, queue | Flexible Server B1ms, free for 12 months |
| Azure OpenAI | embeddings, bot answers | extraction happens in-session (ADR 0005), so pennies |
| Azure Bot Service | Teams channel | F0 tier is free |
| Image registry | container images | **open:** GHCR (free, current choice) or ACR (~5 USD/month) |

Secrets in Container Apps configuration, no separate Key Vault.

**Outside the infrastructure:** this repository holds the code, prompts and golden set.

Two cost decisions (ADR 0004): **one container instead of three services** (the worker runs as a background task in the same process) and **a queue in Postgres instead of Redis**. Target bill: 0–5 USD/month in the first year, then roughly 15–20 USD.

**Database alternative once the free year ends:** [Neon](https://neon.com) — serverless Postgres with pgvector and a native Azure integration, free tier with no time limit (750 MB, 100 CU-h/month), which covers our scale comfortably. Since it is ordinary Postgres, migration is a dump and a connection string change — the decision can wait for real usage data.

## Principles

- **Postgres is the whole thing.** Facts, history and vectors in one place.
- **Nothing enters the database without human approval.** The model only proposes.
- **`fact_versions` is append-only.** The one thing Git gave for free that must be deliberately rebuilt.
- **Fail open on the client side.** A dead server must never slow down or block a developer session.
- **Prompt and classifier versioning**, so past candidates can be reclassified — never touching approved facts.
- **`tenant` is a filter, not a security boundary** (ADR 0001) — it keeps answers from mixing projects.

## How we know it works

- `recall@5` on the golden set ≥ 0.7 (0.6 to start).
- Onboarding a new person: weeks → days.
- Fewer "how does this work?" questions aimed at seniors.
- A week of team work yields at most twenty `domain` candidates per project, at least half of them approved. *(Too many means noise is getting through; too few means knowledge is not being captured.)*

## Order of work

Local first, cloud last — see `action-plan.md` for the detail.

| Phase | What | Where |
|---|---|---|
| 0 | Schema, 50–100 hand-written facts, golden question set | local |
| 1 | Embeddings, vector search only, baseline `recall@5` | local |
| 2 | Quality experiments: hybrid, reranking, query rewriting, tracing | local |
| 3 | MCP server wired into the coding agent | local |
| 4 | Write path: `/fact`, deduplication, minimal review UI | local |
| 5 | Container, Azure Postgres, Container Apps, backup | cloud |
| 6 | Teams bot, answer generation, answer evaluation | cloud |
| 7 | Prompt regression tests, database decision, remaining options | cloud |

Two reasons for this order. **Read path before write path:** if a hundred hand-written facts produce no value, collecting them automatically will not either. **Local before cloud:** everything through Phase 4 runs on a laptop and is already useful to one person, so the infrastructure work only starts once the idea has proven itself. Phase 2 is the decision point for the whole project.

## Risks

- **Retrieval quality is ours now**, not a vendor's. The measure is `recall@5`; failing to reach 0.7 is the signal to move to Azure AI Search, not to tune forever. Switching is cheap — Postgres stays the source of truth, only the index layer changes.
- **Backup is critical.** After ADR 0002 there is no second copy of the facts. A nightly dump and a **tested restore**, not just a declared one.
- **Dependence on discipline.** After ADR 0005 nobody runs `/fact` for the developer. Low fact volume is a real risk; the first response is a lightweight hook reminder, not a return to transcript collection.
- **The `domain` / `engineering` line is blurry.** A human in the loop plus labelled decisions keep it usable.
- **Review fatigue** — if people stop clicking the cards, the system dies quietly. That is why the twenty-candidates-a-week limit is a measure, not trivia.
- **A client with a real NDA** overturns ADR 0001.

## Open questions

1. **Embedding model** — fixes the vector column width, so it must be settled before the schema. Starting point: `text-embedding-3-small`.
2. **LLM for bot answers** — which provider, daily cost cap.
3. **Fact owners** — who is allowed to approve.
4. **Identity** — static tokens to start, or Entra ID / OIDC straight away.
5. **Code connectors** — whether to index project pull requests and issues, or facts only.

Items 1–2 need closing before any code. The rest can wait for the relevant phase.

---

*The original concept this grew from (in Polish) lives outside this repository; the decisions that diverge from it are recorded in `adrs/`.*
