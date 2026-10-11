-- Phase 0 schema. Decisions: ADR 0002 (facts + append-only history),
-- ADR 0003 (embeddings keyed by fact and model), ADR 0007 (JSONB snapshots).

CREATE EXTENSION IF NOT EXISTS vector;

CREATE TYPE fact_status AS ENUM ('candidate', 'approved', 'rejected', 'deprecated');
CREATE TYPE fact_kind   AS ENUM ('business_rule', 'convention');

-- Source of truth. A candidate and an approved fact are the same row.
CREATE TABLE facts (
    id          uuid        PRIMARY KEY,
    tenant      text        NOT NULL,
    statement   text        NOT NULL,
    rationale   text        NOT NULL,
    sources     text[]      NOT NULL,
    status      fact_status NOT NULL,
    kind        fact_kind   NOT NULL,
    tags        text[]      NOT NULL,
    created_by  text        NOT NULL,
    owner       text        NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NULL
);

-- Append-only history: every version, including the current one (ADR 0007).
-- No ON DELETE CASCADE: history is never removed implicitly.
CREATE TABLE fact_versions (
    fact_id        uuid        NOT NULL REFERENCES facts (id),
    version        integer     NOT NULL CHECK (version > 0),
    snapshot       jsonb       NOT NULL,
    changed_by     text        NOT NULL,
    changed_at     timestamptz NOT NULL DEFAULT now(),
    change_reason  text        NULL,
    PRIMARY KEY (fact_id, version)
);

-- Derived data: recomputable from facts, so it goes when the fact goes.
-- `vector` without a dimension holds vectors from any model (ADR 0003);
-- per-model HNSW indexes come in Phase 2.
CREATE TABLE fact_embeddings (
    fact_id       uuid        NOT NULL REFERENCES facts (id) ON DELETE CASCADE,
    model         text        NOT NULL,
    embedding     vector      NOT NULL,
    fact_version  integer     NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (fact_id, model)
);
