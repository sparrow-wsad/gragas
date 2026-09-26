# Brief: a company memory of project facts

The concept in one place, kept current with the decisions in `adrs/`. Where this brief and an ADR disagree, the ADR wins.

| ADR | Decision |
|---|---|
| [0001](adrs/0001-single-instance-no-tenant-isolation.md) | Single instance, tenant isolation is not a security boundary |
| [0002](adrs/0002-postgres-as-source-of-truth.md) | Postgres is the source of truth, no GitHub facts repository |
| [0003](adrs/0003-pgvector-instead-of-onyx.md) | Search on pgvector in Azure Postgres, no Onyx |
| [0004](adrs/0004-single-container-postgres-queue.md) | One application in one container, queue in Postgres |
| [0005](adrs/0005-client-side-extraction.md) | The coding session writes the fact, transcripts stay local |
| [0006](adrs/0006-answering-without-a-chat-channel.md) | Answer generation stays, the Teams chat channel goes |

## The problem

A software house of about ten people runs three technically similar projects for different clients. The differences live in **business rules**, and those rules live in senior developers' heads, in chat threads and in pull request descriptions. The result: slow onboarding, the same "how does this work?" questions over and over, and bugs caused by not knowing a rule. The code does not say it — code shows *how*, not *why*.

## The idea in one sentence

Capture domain facts *during normal work*, put them through a human, store them in Postgres, and serve them from the same database — to coding agents over MCP, and to an answer endpoint that composes cited answers from those facts.

This is an internal developer tool. Nothing goes to a client.

A **fact** is one sentence about system behaviour plus **why**, a source and an owner, written in English. For example: a user without the `admin` role does not see the `organizations` filter on the `fleets` table, because the filter reveals the client's list of organisations — a product decision from PR #412.

## How search works

The whole layer sits in Azure Database for PostgreSQL. The `vector` extension adds a column type and distance operators — it is not a separate service or a separate system.

Retrieval is **hybrid**: vector search captures the meaning of a question, full-text search catches literal table, role and field names. Reciprocal Rank Fusion merges the two result lists. Facts in English let us use the built-in full-text configuration with stemming, without workarounds.

Two thinner strategies sit beside it behind the same function, selected by configuration (ADR 0006): **full text only**, and a **tag-filtered list** where the agent does all the judging. Since every consumer of search is itself an agent, all three are viable — which one wins is a measurement in Phase 2, reported as quality against context cost, not as a single number.

Embeddings live in their own table keyed by fact and model. Changing models therefore means computing a new set alongside the old one and switching after comparing results, rather than migrating blind.

## How it fits together

1. **Write** — the `/fact` command inside a coding session. The agent composes a fact sentence with its rationale and source using the full conversation context; without arguments it proposes one to three facts to confirm on the spot. A finished candidate goes to the server, not a transcript.
2. **Process** — the worker checks whether a similar fact already exists (deduplication) and routes the candidate to review. Candidates marked as engineering conventions become proposals for `.claude/rules/`.
3. **Review** — a human in the loop, always. A minimal candidate list first, Teams approval cards later (approve / reject / it's a convention / edit). Human decisions double as a labelled set for improving classification.
4. **Read** — on approval the embedding is computed and the fact becomes searchable immediately. The coding agent queries over MCP mid-task and composes its own answer. Separately, an answer endpoint takes a question, retrieves facts and writes a cited answer itself — this is where grounding is controlled and measured. Either way every answer cites a fact `id`; no match means "I don't have that recorded" plus a suggestion to run `/fact`.

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
| Memory App | one container: candidate intake, deduplication, review, search, answer generation, MCP server, approval-card endpoint | Container Apps, one replica |

**Azure services**

| Block | Responsibility | Note |
|---|---|---|
| PostgreSQL + `vector` | facts, history, vectors, queue | Flexible Server B1ms, free for 12 months |
| Azure OpenAI | embeddings, answer generation, judge model for evaluation | extraction happens in-session (ADR 0005), so pennies |
| Azure Bot Service | Teams approval cards only, no Q&A (ADR 0006) | F0 tier is free |
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
- Groundedness of generated answers measured, not assumed.
- Onboarding a new person: weeks → days.
- Fewer "how does this work?" questions aimed at seniors.
- A week of team work yields at most twenty `domain` candidates per project, at least half of them approved. *(Too many means noise is getting through; too few means knowledge is not being captured.)*

## Order of work

Local while iterating, deployed once it works — see `action-plan.md` for the detail.

| Phase | What | Where |
|---|---|---|
| 0 | Schema, 50–100 hand-written facts, golden question set | local |
| 1 | Embeddings, vector search only, baseline `recall@5` | local |
| 2 | Retrieval experiments, three strategies compared, tracing | local |
| 3 | Answer generation and its evaluation (groundedness) | local |
| 4 | MCP server and the write path: `/fact`, deduplication, review list | local |
| 5 | Container, Azure Postgres, Container Apps, CI/CD, backup | cloud |
| 6 | Teams approval cards | cloud |
| 7 | Prompt regression tests, database decision, remaining options | cloud |

Two reasons for this order. **Read path before write path:** if a hundred hand-written facts produce no value, collecting them automatically will not either. **Local while iterating:** Phases 0–4 run on a laptop where a change takes seconds to test, then Phase 5 deploys the whole thing properly with a pipeline. Phase 2 is the decision point for the project.

## Risks

- **Retrieval quality is ours now**, not a vendor's. The measure is `recall@5`; failing to reach 0.7 is the signal to move to Azure AI Search, not to tune forever. Switching is cheap — Postgres stays the source of truth, only the index layer changes.
- **Backup is critical.** After ADR 0002 there is no second copy of the facts. A nightly dump and a **tested restore**, not just a declared one.
- **Dependence on discipline.** After ADR 0005 nobody runs `/fact` for the developer. Low fact volume is a real risk; the first response is a lightweight hook reminder, not a return to transcript collection.
- **The `domain` / `engineering` line is blurry.** A human in the loop plus labelled decisions keep it usable.
- **Review fatigue** — if people stop clicking the cards, the system dies quietly. That is why the twenty-candidates-a-week limit is a measure, not trivia.
- **Hallucination in generated answers.** Retrieval metrics do not cover it: the right fact can still produce a wrong answer. Groundedness is measured from Phase 3 onward (ADR 0006).
- **A client with a real NDA** overturns ADR 0001.

## Open questions

1. **Embedding model** — fixes the vector column width, so it must be settled before the schema. Starting point: `text-embedding-3-small`.
2. **LLM for answer generation and judging** — which provider, daily cost cap. Needed by Phase 3, not before.
3. **Fact owners** — who is allowed to approve.
4. **Identity** — static tokens to start, or Entra ID / OIDC straight away.
5. **Code connectors** — whether to index project pull requests and issues, or facts only.

Only item 1 blocks the first line of code. The rest can wait for the relevant phase.

---

*The original concept this grew from (in Polish) lives outside this repository; the decisions that diverge from it are recorded in `adrs/`.*
