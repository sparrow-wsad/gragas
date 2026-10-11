# ADR 0007: Fact history as full JSONB snapshots

- **Status:** accepted
- **Date:** 2026-10-11
- **Depends on:** [ADR 0002](0002-postgres-as-source-of-truth.md)

## Context

ADR 0002 made Postgres the only source of truth and required an append-only `fact_versions` table to answer "who changed this fact, when and why". It did not fix the table's shape. Three questions were left open:

1. Does the table hold only *previous* versions, with the current one living only in `facts`, or *every* version including the current one?
2. Is a version stored column by column, mirroring `facts`, or as a single snapshot of the whole row?
3. How are versions identified and protected from deletion?

The table is a log. It is written on every change and read only when something has gone wrong and someone needs the history of one fact.

## Decision

**Every version is stored, including the current one.** Creating a fact writes version 1; every later change writes the next version. The full history of a fact is one query against one table, with no `UNION` against `facts`.

**The fact's content is stored as one `jsonb` snapshot,** not as columns mirroring `facts`. Change metadata stays in ordinary columns: the fact it belongs to, the version number, who made the change, when, and why.

**The primary key is `(fact_id, version)`.** It identifies a version, and it also detects concurrent edits: two writers who both compute the same next version number collide on the key instead of silently creating a duplicate.

**No `ON DELETE CASCADE`.** Deleting a fact never deletes its history implicitly. Removing a whole tenant, should it ever be needed, is a deliberate bulk operation that deletes versions first and facts second.

## Consequences

**Gained:**
- Adding, renaming or removing a column in `facts` needs no change to `fact_versions`. The log needs no maintenance as the model evolves.
- Each snapshot records the fact exactly as it was at that moment, in the shape it had at that moment.

**Paid:**
- The snapshot is schema-on-read. Old snapshots keep their old shape, so code reading history must tolerate missing or renamed keys.
- The database does not check types or constraints inside the snapshot. Correctness depends on the code that writes it.
- Querying by content is clumsier (`snapshot->>'status'` instead of `status`). This is acceptable because history is read per fact, not searched.
- The current version is stored twice, in `facts` and in `fact_versions`. At a few hundred facts this costs nothing.

## Alternatives considered

- **Only previous versions in `fact_versions`.** No duplication, but reading the full history needs two tables, and a fact has no history entry until its first change. Rejected.
- **Columns mirroring `facts`.** Typed and constrained, with simple queries, but every change to `facts` must be repeated in `fact_versions`. Older rows then hold `NULL` in columns that did not exist when they were written. Rejected for a table that is a log rather than a working set.
- **A surrogate `id` as the primary key.** Works, but needs a separate unique constraint on `(fact_id, version)` to get the same concurrency protection. Rejected as redundant.
