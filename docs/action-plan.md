# Action plan

Current as of the decisions in `adrs/` (0001–0005). Concept: `brief.md`. Diagram: `architecture.mermaid`. Optional extensions: `ai-extensions.md`.

This is a learning project. The order below is chosen so that the AI engineering work comes first and the infrastructure work comes last — not the other way round.

## Governing principles

**Local first.** Everything up to and including the write path runs on a laptop: Postgres in a container, a Python script, no cloud resources. The cloud is needed only when other people have to use it.

**Measure every change.** No retrieval change is "done" until there is a before-and-after number from the golden set. Guessing whether something helped is the habit this project exists to break.

**Read path before write path.** If a hundred hand-written facts produce no value, collecting them automatically will not either.

## Before the first line of code

| Decision | Why it blocks |
|---|---|
| Embedding model | fixes the vector column width in the schema |
| Code ownership with the employer | the repository is public |

The LLM choice can wait — it is not needed until answers are generated in Phase 6.

---

# Part I — local

Nothing in this part touches Azure. By the end of it the system is genuinely useful to one person: you.

## Phase 0 — data and schema

Postgres running locally in a container, with the `vector` extension. Schema: `facts`, `fact_versions`, `fact_embeddings`. Fifty to a hundred facts from one project, written by hand. A golden set of fifty questions, each with the fact `id` it should return.

Write the golden set **before** building search. Written afterwards, it will unconsciously be shaped to match what already works.

**You learn:** vector column types, why embeddings live in their own table, what a usable fact looks like.

**Done when:** a hundred facts and fifty questions exist, and someone who knows the project confirms the facts are true.

## Phase 1 — first retrieval, first measurement

Embed the facts. Implement **vector search only** — no full-text yet. Write the evaluation script that computes `recall@5` over the golden set.

Resist adding hybrid search here. You want a deliberately imperfect baseline, so the next phase has something to improve on and a number to prove it.

**You learn:** embeddings in practice, cosine distance, what `recall@5` actually measures, why a golden set is the foundation of everything else.

**Done when:** the script prints a number. Whatever it is, that number is the baseline.

## Phase 2 — quality experiments

The core of the learning. Each step is one change, one measurement, one commit recording what happened.

| Experiment | Question it answers |
|---|---|
| Add full-text search and RRF | how much does hybrid beat pure vector? |
| Swap the embedding model | is `large` worth the extra cost over `small`? |
| Add reranking | biggest single jump in most RAG systems — is it here? |
| Rewrite queries before searching | do people ask in different words than the facts use? |
| Break the query on purpose | what does a bad retriever look like, so you recognise one later |

Add **tracing** at the start of this phase (Langfuse, self-hosted locally). Every model call recorded: input, output, latency, cost. Without it you are debugging blind, and this is the phase with the most to debug.

**You learn:** hybrid retrieval, RRF, reranking, query rewriting, tracing — and the habit of not trusting an improvement you cannot measure.

**Done when:** `recall@5 ≥ 0.6` and you can say, with numbers, which change bought which part of the gain.

**This is the decision point for the whole project.** Failing to get there, or getting there and finding the answers still useless, means stopping and rethinking — not moving on.

## Phase 3 — MCP, still local

An MCP server with two tools (`memory_search`, `fact_get`), wired into your own coding agent over stdio. Now the agent queries the fact base while you work.

This is where the project first pays for itself, with no cloud involved.

**You learn:** the MCP protocol, tool design for agents, how retrieval quality feels in real use rather than in a metric.

**Done when:** the agent reaches for facts unprompted during a real task and cites them.

## Phase 4 — write path

The `/fact` command in the plugin: the agent composes a fact from session context and posts a finished candidate. Deduplication against existing facts. A minimal review list — a plain HTML page is enough.

Still local. Still one user.

**You learn:** designing an agent command, structured output, deduplication by vector similarity, human-in-the-loop as a pattern.

**Done when:** a week of your own work produces facts you would actually want to keep, and adding one takes seconds rather than interrupting the task.

---

# Part II — cloud

Only worth starting once Part I proves the idea. Everything here is software engineering, not AI engineering — useful, but not what you came for.

## Phase 5 — deployment

Package the application into one container. Azure Database for PostgreSQL with `vector`. Azure Container Apps, one replica, scale to zero. Image in GHCR. Secrets in container configuration. Backup with a **tested restore** — after ADR 0002 there is no second copy of the facts.

**Done when:** two or three colleagues use it from their own machines over MCP.

## Phase 6 — Teams and answers

Teams Q&A bot over Azure Bot Service. Answer generation with citations. Review cards. This is the first point where the system *writes* rather than *retrieves*, so it is also where answer evaluation starts: **groundedness**, **answer relevance** (see `ai-extensions.md`).

Retrieval metrics do not cover this. A correct fact can still produce a wrong answer.

**Done when:** three projects in the system, `recall@5 ≥ 0.7` on each, and bot answers are measurably grounded in the facts they cite.

## Phase 7 — maturity

Convention proposals for `.claude/rules/`. Regression tests for prompts in CI. Database decision once the free year ends (Azure Postgres or Neon). Automatic transcript collection — only if `/fact` proves insufficient (ADR 0005).

---

## Measures

- `recall@5` on the golden set ≥ 0.7 (0.6 to pass Phase 2)
- onboarding a new person: weeks → days
- fewer "how does this work?" questions aimed at seniors
- at most twenty candidates per project per week, at least half approved

## What to watch

**Reaching for the cloud too early.** The pull to deploy something is strong, and deployment feels like progress. It is not, until Phase 2 produces a number worth deploying.

**Whether people actually use `/fact`.** After ADR 0005 it is the only entry point for new facts. Noticeably fewer than twenty candidates per project per week calls for a lightweight hook reminder, computed locally with no model call — not a return to transcript collection.

**Review fatigue.** If people stop clicking the cards, the system dies quietly and nobody reports it.

**Cold start versus the Teams bot.** Scale-to-zero saves the entire compute cost, but the bot has a limited response window. To be measured in Phase 6; the workaround is a minimum replica during working hours.
