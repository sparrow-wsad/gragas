# Action plan

Current as of the decisions in `adrs/` (0001–0006). Concept: `brief.md`. Diagram: `architecture.mermaid`. Optional extras: `ai-extensions.md`.

This is a learning project. The order below puts the AI engineering work first and the infrastructure work second — but everything built does get deployed, because running it properly is part of the goal.

## Governing principles

**Local while iterating, deployed once it works.** Phases 0–4 run on a laptop, where a change takes seconds to test. Phase 5 puts the whole thing in Azure with a proper pipeline — not as an afterthought, as its own piece of work.

**Measure every change.** No retrieval or answer change is finished until there is a before-and-after number from the golden set.

**Read path before write path.** If a hundred hand-written facts produce no value, collecting them automatically will not either.

## Before the first line of code

| Decision | Why it blocks |
|---|---|
| Embedding model | fixes the vector column width in the schema |
| Code ownership with the employer | the repository is public |

---

# Part I — local

Fast iteration, no cloud resources. By the end the system is genuinely useful to one person and every core idea has been measured.

## Phase 0 — data and schema

Postgres running locally in a container, with the `vector` extension. Schema: `facts`, `fact_versions`, `fact_embeddings`. Fifty to a hundred facts from one project, written by hand. A golden set of fifty questions, each with the fact `id` it should return.

Write the golden set **before** building search. Written afterwards, it will unconsciously be shaped to match whatever already works.

**You learn:** vector column types, why embeddings live in their own table, what a usable fact looks like.

**Done when:** a hundred facts and fifty questions exist, and someone who knows the project confirms the facts are true.

## Phase 1 — first retrieval, first measurement

Embed the facts. Implement **vector search only** — no full text yet. Write the evaluation script that computes `recall@5` over the golden set.

Resist adding hybrid search here. You want a deliberately imperfect baseline, so the next phase has something to improve and a number to prove it with.

**You learn:** embeddings in practice, cosine distance, what `recall@5` measures, why the golden set underpins everything else.

**Done when:** the script prints a number. Whatever it is, that is the baseline.

## Phase 2 — retrieval experiments

The core of the learning. One change, one measurement, one commit recording what happened.

| Experiment | Question it answers |
|---|---|
| Add full text and RRF | how much does hybrid beat pure vector? |
| Swap the embedding model | is `large` worth the extra cost over `small`? |
| Add reranking | usually the biggest single jump — is it here? |
| Rewrite queries before searching | do people ask in different words than the facts use? |
| Break the query on purpose | what does a bad retriever look like, so you recognise one later |

Then the comparison that matters most here (ADR 0006): **three search strategies side by side** — hybrid, full text only, tag-filtered list. All three behind one function selected by configuration, never commented out. Report quality against cost:

| Strategy | `recall@5` | tokens returned | cost per call |
|---|---|---|---|
| hybrid | ? | ~500 | embedding per query |
| full text only | ? | ~2000 | none |
| tag list | ? | ~15 000 | none |

A thin server can win on `recall@5` simply by returning more, while eating the agent's context window. One number will not settle this.

Add **tracing** at the start of this phase (Langfuse, self-hosted locally): every model call recorded with input, output, latency and cost. This is the phase with the most to debug.

**You learn:** hybrid retrieval, RRF, reranking, query rewriting, tracing, and the habit of not trusting an improvement you cannot measure.

**Done when:** `recall@5 ≥ 0.6`, and you can say with numbers which change bought which part of the gain.

**This is the decision point for the whole project.** Failing to get there, or getting there and finding the results useless, means stopping and rethinking — not moving on.

## Phase 3 — answers and their evaluation

The second half of RAG. A function that takes a question, retrieves facts, and composes an answer citing fact `id`s — refusing with "I don't have that recorded" when nothing matches. Driven from the command line; no channel, no UI.

Then measure it on the same golden set with a judge model: **groundedness** (does every sentence follow from the supplied facts) and **answer relevance** (does it answer the question asked).

Try to make it hallucinate on purpose — ask about something absent from the fact base and see whether it refuses or invents. That failure mode is the one worth recognising by sight.

**You learn:** prompt design for grounded citation and refusal, context assembly and ordering (including *lost in the middle*), LLM-as-judge, what a hallucination looks like in your own system.

**Done when:** answers cite real fact `id`s, refuse when they should, and groundedness is measured rather than assumed.

## Phase 4 — MCP and the write path

An MCP server with `memory_search` and `fact_get`, over stdio, wired into your own coding agent. The `/fact` command: the agent composes a fact from session context and posts a finished candidate. Deduplication against existing facts. A minimal review list — a plain page is enough.

This is where the project first pays for itself, still with nothing in the cloud.

**You learn:** the MCP protocol, tool design for agents, structured output, deduplication by vector similarity, human-in-the-loop as a pattern.

**Done when:** the agent reaches for facts unprompted during real work, and adding a fact takes seconds rather than interrupting the task.

---

# Part II — deployment

Software engineering rather than AI engineering, and worth doing well — running the thing properly is part of what you want out of this.

## Phase 5 — deploy it

One container holding the API, the worker, the MCP server over HTTP and the answer endpoint. Azure Database for PostgreSQL with `vector`. Azure Container Apps, one replica, scale to zero. Image in GHCR. Secrets in container configuration. A build-and-deploy pipeline on push — the point is a repeatable deployment, not clicking through a portal. Backup with a **tested restore**: after ADR 0002 there is no second copy of the facts.

**You learn:** containerising a Python service, managed Postgres, scale-to-zero and cold starts, secret handling, CI/CD.

**Done when:** two or three colleagues use it from their own machines over MCP, and a push to `main` deploys without manual steps.

## Phase 6 — Teams approval cards

The Teams bot in its reduced role (ADR 0006): it presents candidate facts for approve / reject / reclassify. It does not answer questions.

**Done when:** facts can be approved from Teams without opening a browser.

## Phase 7 — maturity

Prompt regression tests in CI, gated on the golden set. Convention proposals for `.claude/rules/`. Database decision once the free year ends (Azure Postgres or Neon). Re-run the three-strategy comparison on a year of real usage. Conversational Q&A — only if anyone actually asks for it; the function already exists and needs only a channel.

---

## Measures

- `recall@5` on the golden set ≥ 0.7 (0.6 to pass Phase 2)
- groundedness measured on generated answers, not assumed
- onboarding a new person: weeks → days
- at most twenty candidates per project per week, at least half approved

## What to watch

**Deploying before there is anything worth deploying.** The pull is strong because deployment feels like progress. Phase 5 exists precisely so it happens properly — after Phase 2 has produced a number.

**Whether people actually use `/fact`.** After ADR 0005 it is the only entry point for new facts. Noticeably fewer than twenty candidates per project per week calls for a lightweight hook reminder, computed locally with no model call — not a return to transcript collection.

**Review fatigue.** If people stop clicking the cards, the system dies quietly and nobody reports it.

**Cold start versus the approval bot.** Scale-to-zero saves the entire compute cost, and with cards rather than chat the response window is far less tight than it would have been for Q&A.
