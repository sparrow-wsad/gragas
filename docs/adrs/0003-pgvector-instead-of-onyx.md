# ADR 0003: Search on pgvector in Azure Postgres, dropping Onyx

- **Status:** accepted
- **Date:** 2026-09-19
- **Depends on:** [ADR 0001](0001-single-instance-no-tenant-isolation.md), [ADR 0002](0002-postgres-as-source-of-truth.md)

## Context

Onyx was meant to be the search and serving layer. The argument was that it provides embeddings, hybrid retrieval, a chat UI, connectors and an MCP server out of the box, instead of us writing all of it.

Three things undermined that choice.

**Hosting cost.** The Onyx documentation puts Standard mode at roughly 12 CPU and 24 GB of RAM. In Azure that is about 250–400 USD per month, whether it runs on a VM or on AKS. The figures in the source material (4 vCPU / 16 GB) were too low. There is a Lite mode under 1 GB of RAM, but it contains **no vector index and no RAG** — it is the chat interface alone, useless for our purpose. Azure Container Apps is not an alternative here: the free grant covers small services, not a stack that needs 24 GB running continuously.

**Scope narrowed by earlier decisions.** After ADR 0001 and 0002, we need one of the five functions Onyx offers:

| Function | Needed |
|---|---|
| Hybrid retrieval and embeddings | yes |
| Chat interface | no — the interface is the Teams bot |
| Connectors to external sources | no — facts come from our own Postgres |
| MCP server | yes, but it is a thin wrapper over any search API |
| Document permissions | no — dropped in ADR 0001 |

**Language of the facts.** Facts will be written in English. PostgreSQL ships with a built-in full-text configuration for English including stemming and stop words, which removes the only technical argument against building our own search layer — the lack of Polish full-text support.

## Decision

The search layer is built on Azure Database for PostgreSQL with the `vector` extension (pgvector). Onyx is removed from the architecture.

Retrieval is hybrid: vector search combined with full-text search, merged using Reciprocal Rank Fusion. Embeddings live in a separate table keyed by fact and model.

## Consequences

**Removed from scope:**
- hosting Onyx: VM or AKS, reverse proxy, TLS, stack upgrades,
- roughly 250–400 USD per month,
- Onyx configuration: connectors, groups, assistant, LLM provider,
- publishing as a separate step — a fact becomes searchable as soon as its embedding is written.

**Added to build:**
- an embedding pipeline triggered on fact approval,
- the hybrid query and its tuning against the golden set,
- an MCP server with two tools, exposed from the existing API,
- answer generation with citations for the Teams bot; the coding agent composes its own answer.

Estimate: under a week of work, against a permanent cost for a stack we would use one fifth of.

**The architecture collapses to a single database.** Facts, their history and their vectors live in the same Postgres. No cross-system synchronisation, no publishing delay.

**Embeddings in a separate table, not a column on the facts table.** Changing the embedding model means recomputing the whole set. A fact-and-model key allows computing the new model alongside the old one, comparing `recall@5` on the golden set, and switching only on a better result — with the option to roll back.

**Risk:** retrieval quality is now our responsibility, not a vendor responsibility. The measure stays `recall@5` on the golden set — if it does not reach 0.7, the signal is to move to Azure AI Search, not to tune indefinitely.

## Alternatives considered

- **Onyx Standard on AKS or a VM** — rejected; cost disproportionate to usage.
- **Azure AI Search** — deferred as the fallback path. The free tier (3 indexes, 50 MB) would hold several hundred facts, with hybrid search and a semantic ranker. Switching is cheap because Postgres remains the source of truth — only the index layer changes. The Serverless Developer tier is in preview and not considered.
- **pg_diskann** — an ANN index available in Azure, in public preview. At a scale of a few hundred facts HNSW is enough and does not tie us to a preview feature.

## To decide before implementation

**The embedding model.** This must be settled before the schema exists, because it fixes the vector column width. With English facts the starting point is `text-embedding-3-small` — smaller dimension, smaller index and lower cost than the `large` variant, with quality to be verified on the golden set.

## Sources

- https://docs.onyx.app/deployment/getting_started/resourcing
- https://learn.microsoft.com/en-us/azure/postgresql/extensions/how-to-use-pgvector
- https://learn.microsoft.com/en-us/azure/search/search-sku-tier
