# ADR 0005: The session extracts the fact, transcripts stay on the machine

- **Status:** accepted
- **Date:** 2026-09-19
- **Depends on:** [ADR 0004](0004-single-container-postgres-queue.md)

## Context

The original plan had `Stop` and `SessionEnd` hooks sending a transcript delta to the server, where a pipeline of three model calls (pre-filter, extractor, classifier) turned raw dialogue into fact candidates.

That approach has three weaknesses.

**A server-side extractor works without context.** It receives a fragment cut out of the middle of a conversation. It does not know which files were read, what was established earlier in the session, or what the project is about. The coding session has all of that and can point to the source of a fact — a file, a test, a pull request number.

**Volume.** Shipping every session transcript from the whole team means a constant stream of data, storing it, a retention policy and secret scrubbing on both sides — all of it purely to reconstruct on the far side the context that was free on the near side.

**Three model calls instead of one.** The pipeline duplicated work the session had already done by reading the conversation.

Running the coding agent headlessly from a hook was also considered. Rejected: it causes recursion (a session started from a hook fires its own hook), it burns developer subscription limits on background processing, and it makes processing depend on whether a laptop is switched on.

## Decision

The fact is written by the **live coding session**, not the server.

The `/fact` command makes the agent compose a fact sentence with its rationale and source, using the full context of the conversation. Called without arguments, it reviews the recent part of the session and proposes one to three facts to confirm on the spot.

What reaches the server is a **finished candidate**, not a transcript. Transcripts never leave the developer machine.

## Consequences

**Removed from scope:**
- hooks collecting transcripts, along with offset and session-state handling,
- the server-side pre-filter, extractor and classifier, with their prompts and versioning,
- the raw events table and the retention policy — a candidate carries its own quote and source,
- secret scrubbing as a critical concern; with no transcripts in transit the risk shrinks to a single text field, which a server-side filter can handle.

**Stays on the server:** deduplication, storage, change history, review, search, embeddings.

**Positive:**
- Candidate quality improves — the model knows the context and can cite a source.
- Company data does not travel beyond developer machines.
- Extraction uses the coding subscription the way it is meant to be used: during interactive work.
- The model API drops to embeddings and bot answer generation.
- Phase 2 shrinks by roughly half.

**Negative:**
- The system depends on human discipline. Nobody will run `/fact` on a developer's behalf, so low fact volume is a real risk.
- Backward reclassification covers only what the agent recorded, not the full source material.
- Candidate quality depends on the prompt version installed locally in the plugin — updating it means distributing the plugin, not deploying the server.

**Signal to react:** if noticeably fewer than the expected twenty facts per project per week are arriving after two weeks, the first step is a **lightweight reminder in a hook** — computed locally, with no model call (for example: a long session in which `/fact` was never used). Only if that fails does automatic transcript collection come back on the table.

## Alternatives considered

- **Hooks shipping transcripts (original plan)** — rejected for the reasons above; kept as an option for a later phase if `/fact` proves insufficient.
- **A hook running the coding agent in the background** — rejected: recursion, subscription limit consumption, dependence on a running machine, no backward reclassification, and questionable alignment with subscription terms.
- **A hook forcing the model to review the conversation at the end of every turn** — rejected: it extends every exchange and consumes limits; users would disable it within days.
- **A hook with a lightweight reminder** — deferred until data shows it is needed. A reminder built blind will be poorly targeted and will teach people to ignore it.
