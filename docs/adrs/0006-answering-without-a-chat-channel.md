# ADR 0006: Answer generation stays, the Teams chat channel goes

- **Status:** accepted
- **Date:** 2026-09-26
- **Depends on:** [ADR 0005](0005-client-side-extraction.md)

## Context

The original concept had a Teams bot answering questions in natural language: a non-technical person asks "why can't an admin be deleted?" and gets an answer with citations. The same bot would also carry review cards for approving facts.

Two things pushed against that.

**The audience narrowed.** This is an internal tool for developers. Nothing goes to a client. The people who query facts during work are the ones using a coding agent, which already reaches the fact base over MCP and composes its own answers. Conversational Q&A for non-technical staff is a hypothesis, not a known need.

**The channel is expensive and teaches nothing.** A Teams chat bot means Azure Bot Service, app registration, identity mapping, Adaptive Cards, a public endpoint and local tunnelling for debugging. All of it is integration work, none of it is about retrieval or generation.

But dropping answer generation with the channel would be a mistake. Retrieval-Augmented **Generation** without the generation half removes: measuring hallucinations (groundedness), prompt design for citation and refusal, context assembly and ordering, and LLM-as-judge evaluation. The coding agent does generate answers, but with a prompt we neither control nor measure — so none of that work would exist in this codebase.

The two are separable. Answer generation is a **function**; Teams chat is a **channel**.

## Decision

**Answer generation stays** — implemented as a function with its own endpoint, exercised locally from the command line long before any deployment. It takes a question, retrieves facts, composes an answer citing fact `id`s, and refuses when nothing matches.

**Answer quality is measured**, on the same golden set as retrieval: groundedness and answer relevance, scored with a judge model.

**The Teams bot is reduced to approval cards.** It presents candidate facts to developers for approve / reject / reclassify. It does not answer questions.

Conversational Q&A is deferred, not deleted. If it is ever wanted, the function already exists and only needs a channel wired to it.

## Consequences

**Kept, and now part of the plan rather than optional:**
- prompt design for grounded, cited answers,
- groundedness and answer relevance metrics with a judge model (previously listed in `ai-extensions.md` as an extension),
- context assembly: how many facts to include, in what order.

**Removed from scope:**
- conversational Q&A in Teams,
- identity mapping from a Teams user to a project for query purposes,
- thumbs-up/down feedback on answers as a planned feature.

**Simplified:** the Teams bot becomes a one-way surface with buttons. No question parsing, no per-user query routing.

**Unchanged:** Azure OpenAI stays in the architecture — it serves embeddings and answer generation. Had generation been dropped with the channel, and had a non-vector retrieval strategy won in the experiments, the model provider would have left the project entirely.

## Related decision: retrieval strategies stay side by side

With no chat bot, **every consumer of search is itself an agent**. That removes the earlier objection to thin-server designs: a bot has no reasoning of its own, an agent does.

Three strategies are therefore worth building and comparing rather than choosing up front:

| Strategy | Where matching happens | Platform cost |
|---|---|---|
| Hybrid — vectors plus full text | server | embedding per query |
| Full text only | server, agent re-ranks | none |
| Tag-filtered list | agent decides entirely | none |

They live behind one search function selected by configuration — **not commented-out code**. Commented branches rot: they are not run, not tested and not type-checked, so a year later they no longer work. A configuration switch keeps all three alive and lets the comparison be re-run at any time on the golden set.

The comparison is reported as quality against cost, not as a single number. A thin server can score better on `recall@5` purely by returning more results, while consuming far more of the agent's context window.
