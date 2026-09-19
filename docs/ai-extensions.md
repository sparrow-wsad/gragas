# AI engineering extensions

Pieces that can be added to this project to make it a full RAG system rather than just a search box. Ordered by when they are worth introducing. None of them are required for the thing to work — each is a separate skill to learn and a separate commit to show.

## First: two different things to measure

This distinction underpins the rest of the list.

**Retrieval evaluation** answers: did the right fact appear among the returned results at all. That is what `recall@5` against the golden set measures, planned from Phase 1.

**Answer evaluation** answers: is what the bot wrote true, and does it follow from the facts it was given. You can retrieve the right fact and still produce a bad answer — the model adds something of its own, or ignores the document it was handed.

The plan currently measures only the first. The second is usually what people mean by "testing the answers".

## Worth doing early

### Answer metrics

Three standard measures for RAG systems:

- **groundedness** (also called faithfulness) — can every sentence of the answer be traced to the supplied facts. This catches fabrication.
- **answer relevance** — does the answer address the question asked rather than an adjacent topic.
- **context precision** — how many of the supplied facts were actually needed. A low value means the prompt is being padded with noise.

These are usually computed with an **LLM as a judge**: a second model receives the question, the context and the answer, and scores it against instructions. It sounds circular, but with a well-written rubric it correlates with human judgement well enough to catch regressions.

Tooling: **Ragas** has the most developed RAG-specific metrics. Alternatives: TruLens, DeepEval.

### Tracing

Recording every model call: what went in, what came back, how long it took, what it cost, which prompt version was used. Without this, debugging an AI system is guesswork — you see a bad answer but cannot tell whether retrieval or generation failed.

**Langfuse** (MIT licence, self-hostable) is the natural fit. Alternative: Arize Phoenix.

Common practice in 2026 is **two tools**: an evaluation framework run offline in CI, and an observability platform for what happens in production. They complement rather than replace each other.

## Improves retrieval quality

### Reranking

After hybrid search, take the top 20–50 results and run them through a cross-encoder model that scores each against the question more accurately than a vector comparison can. Return the best five.

It costs an extra call, but it usually delivers the single largest quality jump in a RAG system. If `recall@5` stalls below the threshold, this is the first thing to try — before changing the embedding model.

### Query rewriting

A user's question is rarely a good search query. "so why can't I see that filter?" contains no word that matches the fact. The model rewrites it into a query containing the technical names, or generates several variants and merges the results.

A variant called **HyDE** goes further: the model writes a hypothetical answer to the question, and that answer's embedding is used for search. It works because an answer resembles a fact linguistically more than a question does.

### Structured output

Rather than asking the model for JSON and hoping, enforce a schema. This removes a whole class of parsing errors and avoids retries on malformed output.

## Later

**User feedback loop** — thumbs up and down under bot answers. Collects the cases where the system fails; the same data grows the golden set.

**Prompt regression tests** — the golden set run automatically on every prompt or model change, with a threshold that blocks the merge. This turns evaluation from a one-off measurement into a safety net.

**Semantic caching** — repeated questions hit a cache matched by vector similarity rather than exact wording. Only worth it once there is noticeable traffic.

## Suggested learning order

1. `recall@5` on the golden set — already in the plan, Phase 1.
2. Tracing — the earlier it exists, the easier everything else is to debug.
3. Answer metrics with a judge model — once the bot starts answering, Phase 3.
4. Reranking — when `recall@5` stops improving through tuning.
5. Query rewriting — when it turns out people ask in different words than the facts use.
6. Regression tests in CI — when there have been enough prompt changes that you stop remembering what worked.
