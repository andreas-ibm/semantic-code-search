# Semantic Code Search — Approaches

This document tracks the different approaches explored for setting up semantic code search infrastructure, including setup steps, outcomes, and lessons learned.

---

## Approach 1: Elasticsearch + ELSER — ❌ Failed

**Outcome:** This approach was abandoned. Deploying ELSER (Elastic Learned Sparse EncodeR), which is required for semantic/vector search in Elasticsearch, requires a paid Elastic licence. It is not available on the free/basic tier.

### Manual Setup Steps

This section outlines the steps taken to set up the Elasticsearch-based infrastructure before the licence limitation was discovered.

#### 1. Acquire Machine and Install Prerequisites

Install required packages on the machine:

```bash
# Install Podman (container runtime)
sudo dnf install podman

# Install Node.js
sudo dnf install nodejs
```

Verify Node.js installation:
```bash
node -v
```

#### 2. Deploy Elasticsearch with Docker/Podman

Following the [Elasticsearch Docker installation guide](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-basic), we deployed Elasticsearch using Podman (Docker-compatible).

##### Create Docker Network
```bash
# Note: The exact command wasn't in bash history, but this is the standard approach
# from the Elasticsearch documentation
podman network create elastic
```

##### Start Elasticsearch Container
```bash
# Run Elasticsearch container with 1GB memory limit
# For machine learning features (like ELSER), use 6GB instead
podman run --name es01 --net elastic -p 9200:9200 -it -m 6GB -e "xpack.ml.use_auto_machine_memory_percent=true" docker.elastic.co/elasticsearch/elasticsearch:9.4.3

```

The command prints the `elastic` user password and enrollment token. Store the password as an environment variable:

```bash
export ELASTIC_PASSWORD="your_generated_password"
```

##### Extract SSL Certificate

Copy the SSL certificate from the container to the host machine:

```bash
sudo podman cp es01:/usr/share/elasticsearch/config/certs/http_ca.crt /home/amartens/http_ca.crt
sudo chmod a+r ${HOME}/http_ca.crt
```

##### Verify Elasticsearch is Running

Test the connection using curl:

```bash
# With certificate verification
curl --cacert ${HOME}/http_ca.crt -u elastic:$ELASTIC_PASSWORD https://localhost:9200

# Or skip certificate verification (not recommended for production)
curl -k -u elastic:$ELASTIC_PASSWORD https://localhost:9200
```

#### 3. Trust the SSL Certificate System-Wide

To avoid needing to specify the certificate with every request, we added it to the system's trusted certificates. This follows guidance from [Baeldung's CA Certificate Management guide](https://www.baeldung.com/linux/ca-certificate-management).

```bash
# Install the certificate to the system trust store (Red Hat/Fedora)
sudo cp ${HOME}/http_ca.crt /etc/pki/ca-trust/source/anchors/
sudo update-ca-trust
```

After this, you can make requests without specifying the certificate:

```bash
curl -u elastic:$ELASTIC_PASSWORD https://localhost:9200
```

#### 4. Set Up the Code Indexer

Clone the [semantic-code-search-indexer](https://github.com/elastic/semantic-code-search-indexer) repository:

```bash
cd ~/git
git clone https://github.com/elastic/semantic-code-search-indexer.git
cd semantic-code-search-indexer/
```

##### Pin to Stable Version

As noted in the indexer's README, the `main` branch may contain breaking changes. We pinned to a known-good commit from October 2025:

```bash
git checkout 2fe4a9a4fefe84252a9c5ffe95875162bdb79cd0
```

##### Install Dependencies and Build

```bash
npm install
npm run build
```

#### 5. Index Code Repositories

With Elasticsearch running and the indexer built, index your code repositories:

```bash
# Index a repository with the --clean flag to start fresh
npm run index -- /path/to/your/repository --clean

# Examples from our setup:
npm run index -- ${HOME}$/git/axis-axis2-java-rampart/ --clean
```

The `--clean` flag removes any existing index data before indexing. Omit it for incremental updates.

### Notes

- The indexer uses environment variables for Elasticsearch connection. Ensure `ELASTIC_PASSWORD` is set.
- Because we have large repositories, we increased the Elasticsearch container memory (use `-m 6GB` instead of `-m 1GB`).
- The indexer respects `.gitignore` files and can use `.indexerignore` for additional exclusions.
- For production deployments, refer to the [indexer's README](https://github.com/elastic/semantic-code-search-indexer/blob/2fe4a9a4fefe84252a9c5ffe95875162bdb79cd0/README.md) for configuration options and best practices.

### References

- [Elasticsearch Docker Installation (Basic)](https://www.elastic.co/docs/deploy-manage/deploy/self-managed/install-elasticsearch-docker-basic)
- [Baeldung: CA Certificate Management on Linux](https://www.baeldung.com/linux/ca-certificate-management)
- [Semantic Code Search Indexer (GitHub)](https://github.com/elastic/semantic-code-search-indexer)
- [Indexer Documentation (pinned version)](https://github.com/elastic/semantic-code-search-indexer/blob/2fe4a9a4fefe84252a9c5ffe95875162bdb79cd0/README.md)

---

## Approach 2: CocoIndex — ✅ Working (semantic search), ⚠️ Limitation (exact-name search)

**Stack:** CocoIndex (Python, Rust core) + PostgreSQL/pgvector + `sentence-transformers` (fully local embeddings — no licence, no API key).

**How it meets the requirements:**

| Requirement | How it's met |
|---|---|
| Semantic search | pgvector cosine-similarity over `sentence-transformers` embeddings |
| Large codebases | CocoIndex's incremental Rust engine skips unchanged files on re-runs |
| Multiple codebases | Single app, multiple source dirs — each tagged with its repo name |
| MCP API | CocoIndex built-in MCP server: `cocoindex server mcp main` |
| Containerised | pgvector/pg17 in Podman; CocoIndex app containerisable in a second step |
| C++ / Java / JavaScript | Tree-sitter `RecursiveSplitter` handles all three natively |

---

### Manual Setup Steps

#### 1. Prerequisites

The machine already has **Python 3.12.13** and **Podman 5.8.2** — no additional system installs are needed.

Verify:
```bash
python3 --version   # should be 3.11 or later
podman --version
```

#### 2. Start PostgreSQL + pgvector

CocoIndex stores embeddings in Postgres with the pgvector extension. Run it in Podman:

```bash
podman run -d \
  --name cocoindex-postgres \
  -e POSTGRES_PASSWORD=cocoindex \
  -e POSTGRES_USER=cocoindex \
  -e POSTGRES_DB=cocoindex \
  -p 5432:5432 \
  pgvector/pgvector:pg17
```

Verify it is up:
```bash
podman ps | grep cocoindex-postgres
```

#### 3. Create the Indexer Project

```bash
mkdir -p ~/git/semantic-code-search-cocoindex
cd ~/git/semantic-code-search-cocoindex
```

Create and activate a virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
```

Install dependencies (latest CocoIndex as of writing: **1.0.16**):
```bash
pip install --upgrade pip
pip install \
  "cocoindex[postgres,sentence_transformers]>=1.0.16" \
  "asyncpg>=0.29.0" \
  "pgvector>=0.5.0" \
  "numpy" \
  "python-dotenv>=1.0.1"
```

Create a `.env` file so credentials are loaded automatically:
```bash
cat > .env <<'EOF'
POSTGRES_URL=postgres://cocoindex:cocoindex@localhost/cocoindex
COCOINDEX_DB=./cocoindex.db
PYTORCH_ENABLE_MPS_FALLBACK=1
EOF
```

> **Note:** Activate the venv (`source .venv/bin/activate`) at the start of every session before running any `cocoindex` or `python` commands below.

#### 4. Write the Indexer (`main.py`)

Key design decisions versus the upstream `code_embedding` example:

- **Multiple source repositories** — `app_main` loops over a list of paths, tagging each chunk with its repo name.
- **Language patterns extended** — includes C++, Java, and JavaScript in addition to the upstream defaults.
- **Source paths via environment variable** — no hard-coded paths; set `SOURCE_DIRS` as a colon-separated list.
- **Auto offline after first download** — on startup `main.py` checks whether the model snapshot is already present in `~/.cache/huggingface/hub/`. If it is, `HF_HUB_OFFLINE`, `TRANSFORMERS_OFFLINE`, and `HF_HUB_DISABLE_PROGRESS_BARS` are set before any library imports so subsequent runs are fully silent. On a fresh machine the cache is absent and the flags stay unset, so `cocoindex update main` downloads the model automatically on its first run. `OfflineEmbedder` also passes `local_files_only=True` to `SentenceTransformer` once cached.

Create `main.py` (or copy from `implementation-cocoindex/main.py`):

```python
"""
Semantic Code Search — CocoIndex Indexer

Index (one-shot):
    cocoindex update main

Index (live watch — re-embeds on file save):
    cocoindex update -L main

Query:
    python main.py "your query here"
"""

from __future__ import annotations

import asyncio
import os
import pathlib
import sys
from dataclasses import dataclass
from dotenv import load_dotenv
from typing import AsyncIterator, Annotated

# Go offline if the model is already cached — avoids HF Hub network calls and
# the "unauthenticated requests" warning on every query.  When the cache is
# absent (first run on a new machine) these stay unset so the model downloads
# normally.  Users can force either mode by setting these vars in their shell
# or .env before running.
def _model_cache_exists(model_id: str) -> bool:
    """Return True if *any* snapshot of model_id exists in the HF hub cache."""
    cache_dir = pathlib.Path(
        os.environ.get("HF_HUB_CACHE", os.path.expanduser("~/.cache/huggingface/hub"))
    )
    slug = "models--" + model_id.replace("/", "--")
    snapshots = cache_dir / slug / "snapshots"
    return snapshots.is_dir() and any(snapshots.iterdir())


if _model_cache_exists("sentence-transformers/all-MiniLM-L6-v2"):
    os.environ.setdefault("HF_HUB_OFFLINE", "1")
    os.environ.setdefault("TRANSFORMERS_OFFLINE", "1")
    os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")

import asyncpg
from pgvector.asyncpg import register_vector
from numpy.typing import NDArray

import cocoindex as coco
from cocoindex.connectors import localfs, postgres
from cocoindex.ops.text import RecursiveSplitter, detect_code_language
from cocoindex.ops.sentence_transformers import SentenceTransformerEmbedder
from cocoindex.resources.chunk import Chunk
from cocoindex.resources.file import FileLike, PatternFilePathMatcher
from cocoindex.resources.id import IdGenerator

load_dotenv()

DATABASE_URL = os.environ["POSTGRES_URL"]
TABLE_NAME = "code_embeddings"
PG_SCHEMA_NAME = "semantic_search"
TOP_K = 5
EMBED_MODEL = "sentence-transformers/all-MiniLM-L6-v2"

# Source directories — set SOURCE_DIRS in .env as a colon-separated list of paths
_DEFAULT_DIRS = os.getenv("SOURCE_DIRS", "/var/repositories/axis-axis2-java-rampart")
SOURCE_DIRS = [pathlib.Path(p) for p in _DEFAULT_DIRS.split(":") if p]

# Language patterns: C++, Java, JavaScript, plus Python / Rust / Markdown
INCLUDED_PATTERNS = [
    "**/*.py",
    "**/*.rs",
    "**/*.cpp", "**/*.cc", "**/*.cxx", "**/*.c", "**/*.h", "**/*.hpp",
    "**/*.java",
    "**/*.js", "**/*.ts", "**/*.jsx", "**/*.tsx",
    "**/*.md", "**/*.mdx",
    "**/*.toml",
]
EXCLUDED_PATTERNS = [
    "**/.*", "**/target", "**/node_modules", "**/build", "**/dist",
]


class OfflineEmbedder(SentenceTransformerEmbedder):
    """SentenceTransformerEmbedder that suppresses HF Hub traffic when cached.

    Passes local_files_only=True only when HF_HUB_OFFLINE is active (i.e. the
    cache already exists).  On a fresh machine the flag stays False so the
    model is downloaded normally on first use.
    """

    def _get_model(self):  # type: ignore[override]
        if self._model is None:
            with self._lock:
                if self._model is None:
                    from sentence_transformers import SentenceTransformer
                    self._model = SentenceTransformer(
                        self._model_name_or_path,
                        device=self._device,
                        trust_remote_code=self._trust_remote_code,
                        local_files_only=os.environ.get("HF_HUB_OFFLINE") == "1",
                    )
        return self._model


PG_DB = coco.ContextKey[asyncpg.Pool]("code_embedding_db")
EMBEDDER = coco.ContextKey[OfflineEmbedder]("embedder", detect_change=True)

_splitter = RecursiveSplitter()


@dataclass
class CodeEmbedding:
    id: int
    repo: str        # top-level source directory name
    filename: str
    code: str
    embedding: Annotated[NDArray, EMBEDDER]
    start_line: int
    end_line: int


@coco.lifespan
async def coco_lifespan(builder: coco.EnvironmentBuilder) -> AsyncIterator[None]:
    async with asyncpg.create_pool(DATABASE_URL) as pool:
        builder.provide(PG_DB, pool)
        builder.provide(EMBEDDER, OfflineEmbedder(EMBED_MODEL))
        yield


@coco.fn
async def process_chunk(
    chunk: Chunk,
    repo: str,
    filename: pathlib.PurePath,
    id_gen: IdGenerator,
    table: postgres.TableTarget[CodeEmbedding],
) -> None:
    embedding = await coco.use_context(EMBEDDER).embed(chunk.text)
    table.declare_row(
        row=CodeEmbedding(
            id=await id_gen.next_id(chunk.text),
            repo=repo,
            filename=str(filename),
            code=chunk.text,
            embedding=embedding,
            start_line=chunk.start.line,
            end_line=chunk.end.line,
        )
    )


@coco.fn(memo=True)
async def process_file(
    file: FileLike,
    repo: str,
    table: postgres.TableTarget[CodeEmbedding],
) -> None:
    text = await file.read_text()
    language = detect_code_language(filename=str(file.file_path.path.name))
    chunks = _splitter.split(
        text, chunk_size=1000, min_chunk_size=300, chunk_overlap=300, language=language,
    )
    id_gen = IdGenerator()
    await coco.map(process_chunk, chunks, repo, file.file_path.path, id_gen, table)


@coco.fn
async def app_main() -> None:
    table = await postgres.mount_table_target(
        PG_DB,
        table_name=TABLE_NAME,
        table_schema=await postgres.TableSchema.from_class(
            CodeEmbedding, primary_key=["id"]
        ),
        pg_schema_name=PG_SCHEMA_NAME,
    )
    table.declare_vector_index(column="embedding")

    for src in SOURCE_DIRS:
        files = localfs.walk_dir(
            src,
            recursive=True,
            path_matcher=PatternFilePathMatcher(
                included_patterns=INCLUDED_PATTERNS,
                excluded_patterns=EXCLUDED_PATTERNS,
            ),
            live=True,
        )
        await coco.mount_each(process_file, files.items(), src.name, table)


app = coco.App(coco.AppConfig(name="SemanticCodeSearch"), app_main)


# ─── Query CLI ────────────────────────────────────────────────────────────────

async def query_once(
    pool: asyncpg.Pool,
    embedder: OfflineEmbedder,
    query: str,
    *,
    top_k: int = TOP_K,
) -> None:
    query_vec = await embedder.embed(query)
    async with pool.acquire() as conn:
        rows = await conn.fetch(
            f"""
            SELECT repo, filename, code, start_line, end_line,
                   embedding <=> $1 AS distance
            FROM "{PG_SCHEMA_NAME}"."{TABLE_NAME}"
            ORDER BY distance ASC
            LIMIT $2
            """,
            query_vec, top_k,
        )
    for r in rows:
        score = 1.0 - float(r["distance"])
        print(f"[{score:.3f}] {r['repo']}/{r['filename']} (L{r['start_line']}-L{r['end_line']})")
        print(f"    {r['code'][:200]}")
        print("---")


async def query(initial_query: str | None = None) -> None:
    embedder = OfflineEmbedder(EMBED_MODEL)
    async with asyncpg.create_pool(DATABASE_URL, init=register_vector) as pool:
        if initial_query is not None:
            await query_once(pool, embedder, initial_query)
            return
        while True:
            q = input("Query (Enter to quit): ").strip()
            if not q:
                break
            await query_once(pool, embedder, q)


if __name__ == "__main__":
    initial = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else None
    asyncio.run(query(initial))
```

#### 5. Index the Small Test Repository

Use the small `axis-axis2-java-rampart` repo (17 MB, Java) for the first test run.

```bash
# Ensure the venv is active
source .venv/bin/activate

# Point at the small repo
export SOURCE_DIRS="/var/repositories/axis-axis2-java-rampart"

# One-shot index (exits when complete)
cocoindex update main
```

On first run this will:
1. Download `all-MiniLM-L6-v2` (~90 MB) to `~/.cache/huggingface/hub/`. All subsequent runs detect the cache and switch to fully-offline mode automatically — no warnings, no network calls.
2. Walk the repo, chunk every matching file with Tree-sitter, embed each chunk, and upsert into pgvector.
3. Print a progress summary and exit.

#### 6. Verify with a Search Query

```bash
python main.py "SOAP message signing"
```

Expected output: several Java snippets returned with similarity scores, pointing at relevant line ranges in the Rampart source.

#### 7. Index a Large Repository (Optional)

Once the small repo is confirmed working, point `SOURCE_DIRS` at one or both of the large repos:

```bash
export SOURCE_DIRS="/var/repositories/ace-runtime:/var/repositories/ace-toolkit"
cocoindex update main
```

CocoIndex's incremental engine means subsequent runs only re-embed files that have changed — no full re-index.

#### 8. Start the MCP Server

CocoIndex ships a built-in MCP server. After the index is populated:

```bash
cocoindex server mcp main
```

AI agents (Bob, Claude Code, Cursor, etc.) can then be pointed at this endpoint for semantic code search via MCP.

### Results

Semantic / intent-based queries work well. For example:

```bash
python main.py "create Policy from xml file"
```

Returns a highly relevant result (score ~0.699):

```
[0.699] axis-axis2-java-rampart//var/repositories/axis-axis2-java-rampart/modules/rampart-samples/policy/sample05/src/org/apache/rampart/samples/policy/sample05/Client.java (L120-L138)
    private static Policy loadPolicy(String xmlPath) throws Exception {
        java.io.File policyFile = new java.io.File(xmlPath);

        if (!policyFile.exists()) {
            throw new Exception("Policy file not found
```

**Known limitation — exact symbol/name lookup:** Searching for the exact function name `loadPolicy` returns no useful results. The embedding model maps short identifiers to a different part of the vector space than natural-language intent queries, so a literal token like `loadPolicy` does not match the relevant chunk by cosine similarity.

This is a fundamental property of dense-vector (semantic) search: it excels at *meaning*, not at *spelling*. The solution is to combine it with keyword/lexical search (see [Approach 3](#approach-3-hybrid-search-plan) below).

---

### Notes

- Always `source .venv/bin/activate` before running `cocoindex` or `python main.py`.
- The `all-MiniLM-L6-v2` model runs fully locally — no API key or paid service required. On the first `cocoindex update main` run the model is downloaded automatically; after that `main.py` detects the local cache and switches to offline mode silently.
- CocoIndex stores its internal change-tracking state in a SQLite file (`cocoindex.db`) in the project directory. Vector data lives in Postgres.
- If the Postgres container is restarted, the app reconnects automatically on the next run.
- PL/1, Bash, and Perl are not natively recognised by Tree-sitter's language detector; they fall back to plain-text splitting, which still works for semantic search but won't respect syntax boundaries.

### References

- [CocoIndex GitHub](https://github.com/cocoindex-io/cocoindex)
- [code_embedding example](https://github.com/cocoindex-io/cocoindex/tree/main/examples/code_embedding)
- [CocoIndex docs](https://cocoindex.io/docs/)
- [pgvector/pgvector Docker image](https://hub.docker.com/r/pgvector/pgvector)

---

## Approach 3: Hybrid Search — ✅ Implemented

**Goal:** Combine the semantic search from Approach 2 with a keyword/lexical layer so that both intent queries (`"create Policy from xml file"`) and exact-name queries (`"loadPolicy"`) return useful results.

**Files (in git — no copy/paste required):**
- [`implementation-cocoindex/main_hybrid.py`](implementation-cocoindex/main_hybrid.py) — drop-in replacement for `main.py`; indexing pipeline is identical, query side is extended.
- [`implementation-cocoindex/migrate_hybrid.sql`](implementation-cocoindex/migrate_hybrid.sql) — one-time migration that adds the required indexes.

### Problem Statement

| Query type | Example | Dense vector search | Keyword search |
|---|---|---|---|
| Intent / concept | `"XML policy loading"` | ✅ Strong | ❌ Weak |
| Exact identifier | `"loadPolicy"` | ❌ Weak | ✅ Strong |
| Mixed | `"loadPolicy signature"` | ⚠️ Partial | ⚠️ Partial |

A hybrid system handles all three by running both searches in parallel and merging the ranked lists before presenting results.

### Design

#### Search modes

The `--mode` / `-m` CLI flag selects the search strategy (default: `both`):

| `--mode` | Behaviour |
|---|---|
| `semantic` | Cosine similarity only (identical to the original `main.py`) |
| `keyword` | PostgreSQL full-text search + trigram `ILIKE` fallback for identifiers |
| `both` | Both legs run in parallel; results merged with Reciprocal Rank Fusion (RRF) |

#### Keyword search backend

PostgreSQL already stores the `code` text in `code_embeddings`. Two complementary indexes are added by the migration:

1. **`tsvector` GIN index** — `CREATE INDEX … USING GIN (to_tsvector('english', code))`. Used by `websearch_to_tsquery` / `ts_rank_cd` for multi-word queries.
2. **Trigram GIN index** (`pg_trgm`) — `CREATE INDEX … USING GIN (code gin_trgm_ops)`. Used by `ILIKE '%loadPolicy%'` for single-token exact-name lookups. camelCase and snake_case identifiers tokenise poorly in English full-text dictionaries, so the trigram path handles them instead.

The `keyword_search()` function automatically selects the right path:
- Single-token query → union of full-text + `ILIKE`, deduplicated.
- Multi-token query → full-text only.

#### Result merging — Reciprocal Rank Fusion (RRF)

```
rrf_score(d) = Σ  1 / (k + rank(d, list_i))
```

*k* = 60 (standard default from the original Cormack & Clarke paper). Each result list contributes independently; a document appearing in both lists scores higher than one appearing in only one. De-duplication key: `(filename, start_line)`.

The score column in the output is labelled with the source (`semantic`, `keyword`, or `both`) so it is clear which leg(s) contributed each result.

### Manual Setup Steps

#### 1. Prerequisites

Same as Approach 2. No new system packages are required — `pg_trgm` is bundled with the standard `pgvector/pgvector:pg17` image.

#### 2. Run the migration

This adds the two indexes to the already-populated table. No data changes, no re-indexing.

```bash
# Ensure the venv is active and .env is loaded
source .venv/bin/activate
export $(grep -v '^#' .env | xargs)

psql "$POSTGRES_URL" -f migrate_hybrid.sql
```

Expected output:

```
CREATE INDEX
CREATE EXTENSION
CREATE INDEX
```

#### 3. Use `main_hybrid.py` instead of `main.py`

The indexing commands are identical — just replace `main` with `main_hybrid`:

```bash
# One-shot index
cocoindex update main_hybrid

# Live watch
cocoindex update -L main_hybrid
```

#### 4. Query

```bash
# Default: hybrid (both legs, RRF merged)
python main_hybrid.py "create Policy from xml file"
python main_hybrid.py "loadPolicy"

# Explicit mode
python main_hybrid.py --mode semantic "SOAP message signing"
python main_hybrid.py --mode keyword  "loadPolicy"
python main_hybrid.py -m both         "loadPolicy XML"
```

Output format includes the source tag:

```
[0.0159|both] axis-axis2-java-rampart/…/Client.java (L120-L138)
    private static Policy loadPolicy(String xmlPath) throws Exception {
---
```

The score in `both` mode is the RRF score (not a similarity percentage); higher is still better.

#### 5. Interactive mode

```bash
python main_hybrid.py           # hybrid, interactive
python main_hybrid.py --mode keyword   # keyword-only, interactive
```

### Results

Hybrid mode with `python main_hybrid.py "loadPolicy"` produced:

```
[0.0164|semantic] …/AsymmetricBindingBuilder.java (L19-L36)   — import block (not relevant)
[0.0164|keyword]  …/KerberosPolicyTest.java (L89-L103)         — calls loadPolicy(policyFile) ✅ usage found
[0.0161|semantic] …/RampartUtil.java (L283-L295)               — unrelated utility method
[0.0161|keyword]  …/KerberosPolicyTest.java (L105-L119)        — calls loadPolicy(policyFile) ✅ usage found
[0.0159|semantic] …/SupportingPolicyData.java (L20-L42)        — unrelated policy class
```

**Assessment — mostly successful, but with a gap:**

| What worked | What didn't |
|---|---|
| Keyword leg found *usages* of `loadPolicy` (call sites in test files) | Neither leg returned the *definition* of `loadPolicy` as a top-5 result |
| Semantic leg no longer dominates with irrelevant import blocks alone | RRF scores are very close (0.0159–0.0164), so ranking is essentially random at this distance |

**Root cause of the definition miss:** The `ILIKE '%loadPolicy%'` path matches any chunk containing the token — call sites, imports, and the definition all qualify. With `TOP_K = 5` and many call sites in the codebase, the definition chunk can be pushed out of the top 5 by sheer volume of usages. The definition is almost certainly in the index; it just ranked 6th or lower.

**Known remaining limitation:** Pure substring search cannot distinguish a *definition* (`private static Policy loadPolicy(...)`) from a *usage* (`policy = loadPolicy(file)`). Fixing this requires symbol-aware indexing (see Open questions below) — storing definitions and usages as separate, typed rows so that a query like `loadPolicy` can filter to `kind = "definition"` directly.

### Notes

- `migrate_hybrid.sql` is idempotent (`CREATE INDEX IF NOT EXISTS`, `CREATE EXTENSION IF NOT EXISTS`) — safe to run more than once.
- The trigram `ILIKE` fallback matches substrings, so `loadPolicy` will match any chunk containing that token anywhere in the text.
- The RRF constant `k = 60` can be tuned via the `RRF_K` constant at the top of `main_hybrid.py`. Larger `k` flattens the ranking curve; smaller `k` makes top-ranked results dominate more strongly.
- `main_hybrid.py` is a self-contained drop-in: both the indexing pipeline (`cocoindex update`) and the query CLI (`python main_hybrid.py`) work from the same file.

### Open questions / future work

- **Symbol-aware indexing with ctags/LSP:** A deeper integration would index function/class names explicitly as separate rows, giving keyword search a clean, pre-tokenised symbol table. Revisit if pure `ILIKE` precision is insufficient.
- **Reranking:** A cross-encoder reranker (e.g. `cross-encoder/ms-marco-MiniLM-L-6-v2`) applied to the top-N merged results could further improve relevance, at the cost of additional latency.
- **MCP integration:** The hybrid query path should be exposed via the MCP server endpoint as well, not only the CLI.

---

## Future: Automation

Once the manual steps above are confirmed working, the next phase is to containerise and automate:

- [ ] `podman-compose` / `docker-compose.yml` launching Postgres **and** the CocoIndex app together.
- [ ] `Dockerfile` for the CocoIndex Python app (base: `python:3.12-slim`).
- [ ] `SOURCE_DIRS` and `POSTGRES_URL` injected via environment / secrets.
- [ ] Scheduled or triggered re-indexing (git hook → `cocoindex update`, or a systemd timer).
- [ ] Thin HTTP/FastAPI wrapper exposing a `/search` endpoint for a Web UI.
- [ ] Update [`Architecture.md`](Architecture.md) to reflect the CocoIndex-based stack.

---

## Future Approaches

> Additional approaches to be explored and documented here.
