# ADR 0002: Postgres as the source of truth, no GitHub facts repository

- **Status:** accepted
- **Date:** 2026-09-18
- **Depends on:** [ADR 0001](0001-single-instance-no-tenant-isolation.md)

## Context

The original plan used two storage systems: Postgres for raw material (transcripts, candidates, audit) and a Git repository as the source of truth for approved facts, stored as `facts/<tenant>/<ID>.md`. The search layer would only ever be an index, fed after a merge to `main`.

Reviewing the arguments for Git after the decision in ADR 0001:

| Argument for Git | Verdict |
|---|---|
| Handing facts over to a client | Gone — no longer a goal |
| Review in pull requests | A stopgap; review will happen in Teams cards or our own UI |
| Change history, who and why | A versions table does this more precisely |
| Schema validation in CI | A database constraint plus API validation — simpler and faster |
| Editing a fact by hand in an IDE | Real, but developers approve through the UI anyway |
| Backup | `pg_dump` is in the plan regardless |

One argument survives: a `.md` file can be read without any tooling. That is convenience, not a foundation.

On the cost side, two sources of state require synchronisation: a GitHub App and its tokens, a CI validator, a publishing Action, `CODEOWNERS`, conflict handling. It also creates an artificial split — a candidate lives in Postgres while an approved fact lives in Git, even though it is **the same object in a different state**. A question like "show me every fact in this project with status X" needs two systems. Publishing takes four steps (approve → PR → merge → Action → ingest) where one would do.

## Decision

Postgres is the only source of truth for facts. No facts repository is created.

A fact is a row in `facts` — the same record as the candidate, with a different status. Change history goes to `fact_versions` as an **append-only** table: who changed it, when, what the previous content was, and why.

Publishing to the search layer happens directly on approval.

## Consequences

**Removed from scope:**
- the facts repository and its directory structure,
- the GitHub App and its token management,
- the frontmatter validator in CI and source link checking,
- the publishing Action,
- `CODEOWNERS` as an ownership mechanism,
- the pull-request review phase.

**Simplified:**
- publishing: approve in the API → immediate indexing, one step instead of four,
- data model: one table serves both candidate and fact, with no copying between systems,
- operational queries: everything in a single `SELECT`.

**Requires building what Git gave for free:**
- `fact_versions` as append-only. Without it there is no answer to "who changed this fact and why", which is exactly the question asked when a fact turns out to be wrong. This is the one thing from Git that must be deliberately rebuilt and must not be skipped.
- Validation of required fields moves from CI to database constraints and API validation.
- A minimal review view is needed earlier than planned — pull requests no longer serve as a temporary UI.

**Risk:**
- A single source of truth raises the stakes on backups. A nightly `pg_dump` and a **tested restore** stop being a formality — without Git there is no second copy of the facts.

## Alternatives considered

- **Git as the source of truth (original plan)** — rejected for the reasons above.
- **Git as a one-way export from Postgres** — not now, but the decision is reversible: dumping to `.md` files can be added at any point if a readable copy or an external handover is ever needed.
