# ADR 0001: Single instance, tenant isolation is not a security boundary

- **Status:** accepted
- **Date:** 2026-09-18

## Context

The original concept assumed hard per-client data isolation: an Onyx access group per `tenant`, a mandatory `tenant` filter on every query, negative tests, and a verification checklist before any real data entered the system. The justification was NDA-covered data across three separate client projects.

Checking the Onyx documentation showed that **user groups and per-document permissions are Enterprise Edition only**. The docs state plainly: *"RBAC protection to documents and resources are only available in the Enterprise Edition"* and *"Different access to documents is only available in the Enterprise Edition"*. Community Edition does not provide the layer the plan was built on.

That left three options: pay for Enterprise Edition, run a separate Onyx instance per client, or drop isolation altogether.

The project owner decided: **no private data will be stored**, the projects are technically similar, and responsibility for separation moves to how the data is phrased. Isolation therefore stops being a requirement.

## Decision

A single instance for all projects.

`tenant` stays in the data model as a **filter field**, so answers do not mix contexts across projects. It is not a security boundary.

## Consequences

**Positive:**
- Community Edition is sufficient; no Enterprise licence cost.
- One VM instead of three — lower operating and maintenance cost.
- The isolation part of the verification checklist disappears: two-account tests, negative access tests, verifying refusals through the bot and MCP.
- A simpler permission model in the API — no user-to-tenant map acting as an access control mechanism.

**Negative, and accepted:**
- Any user can reach any project's facts. This is a deliberate choice.
- Onboarding a client with a real NDA would force this decision to be revisited — the cheapest path then is a separate instance, not Enterprise Edition.
- Without a hard boundary, the quality of `tenant` filtering affects answer relevance, not just tidiness.

## Technical note

While verifying the above: the source material mentions Vespa as the index engine and warns about its memory footprint. That is out of date — Onyx moved to OpenSearch, the cloud migration completed in April 2026, and from v3 the switch happens automatically on upgrade. VM sizing should be calculated for OpenSearch, which is likely lower than the assumed 16 GB of RAM.

*(Superseded in practice by [ADR 0003](0003-pgvector-instead-of-onyx.md), which removes Onyx from the architecture entirely. Kept because the isolation decision still stands on its own.)*

## Sources

- https://docs.onyx.app/security/architecture/access_controls
- https://docs.onyx.app/admins/advanced_configs/opensearch_document_index_migration
