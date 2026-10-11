# gragas

A company memory of project facts. It captures domain facts about projects (a rule, its reason, its source), puts them through human review, and serves them to coding agents over MCP and to an answer endpoint that composes cited answers.

Concept, decisions and plan live in [`docs/`](docs/). Start with [`brief.md`](docs/brief.md) and [`action-plan.md`](docs/action-plan.md).

## Status

Phase 0: data and schema. The database runs locally in a container. No application code yet.

## Local database

Requires Docker Desktop (or Docker Engine) with Compose. Each command below is followed by what its parts mean.

### A few words on Docker first

- An **image** is a packaged, read-only template: an operating system, Postgres, and its configuration. We use `pgvector/pgvector:pg17`, which is Postgres 17 with the `vector` extension installed.
- A **container** is a running instance of an image, like an object created from a class. It can be stopped, started and deleted.
- A **volume** is storage that lives outside the container. Deleting the container does not delete the volume, so the database files survive.
- **Compose** reads `compose.yaml` and creates everything it describes (containers, volumes, ports) with one command, instead of a long `docker run ...` with every option spelled out.

### 0. Go to the repository root

```
cd path/to/gragas
```

All commands below run from the directory containing `compose.yaml`. Compose looks for `compose.yaml` and `.env` in the **current directory**. Run from anywhere else, it finds neither.

### 1. Configure

```
cp .env.example .env
```

- `cp`: copy a file. It works in Bash and PowerShell, where `cp` is an alias for `Copy-Item`.
- `.env.example`: the committed template that lists which variables exist.
- `.env`: your local copy with real values. It is git-ignored, so the password never reaches the repository.

Open `.env` and set `POSTGRES_PASSWORD`. Avoid `$` in the password, because Compose treats `$` as the start of a variable and would substitute it.

Compose replaces `${POSTGRES_PASSWORD}` in `compose.yaml` with the value from `.env`. To see the result after substitution:

```
docker compose config
```

- `docker compose`: the Compose tool.
- `config`: validate `compose.yaml` and print it with variables filled in. Nothing is started.

If this prints an error or an empty password, fix it before going further.

### 2. Start Postgres

```
docker compose up -d
```

- `up`: create and start everything in `compose.yaml`. The first time, it downloads the image (a few hundred MB) and creates the volume.
- `-d`: *detached*, which means run in the background and return the prompt. Without it, the terminal shows the database log and closing it stops the database.

What `compose.yaml` sets up:

- `container_name: gragas_db_container`: a fixed name, so later commands can refer to the container.
- `environment`: variables read by the Postgres image **only on first start with an empty volume**. It creates the database `gragas_db` and the user `gragas` with the password from `.env`. Changing the password later has no effect on an existing database. See *Reset*.
- `ports: "5432:5432"`: `host:container`. Port 5432 on your machine forwards to port 5432 inside the container, so tools on your laptop (an IDE, and later Python) can connect to `localhost:5432`.
- `volumes`: mounts the `pgvector_gragas_data` volume at `/var/lib/postgresql/data`, where Postgres keeps its files.

Useful while it runs:

```
docker compose ps
docker compose logs postgres
docker compose stop
docker compose start
```

- `ps`: list this project's containers and their state.
- `logs postgres`: show the log of the `postgres` service, which is the name under `services:` in `compose.yaml`. Add `-f` to follow it live and `Ctrl+C` to stop following.
- `stop` / `start`: stop and start the container without deleting anything.

### 3. Create the schema

Bash or Git Bash:

```
docker exec -i gragas_db_container psql -U gragas -d gragas_db < db/schema.sql
```

PowerShell does not support `<` redirection, so pipe the file instead:

```
Get-Content db/schema.sql | docker exec -i gragas_db_container psql -U gragas -d gragas_db
```

Piece by piece:

- `docker exec`: run a command **inside** a running container. Nothing needs to be installed on your machine, because `psql` comes with the image.
- `-i`: *interactive*, which keeps the container's input open so it can receive data from your terminal. Without it, the SQL file never arrives.
- `gragas_db_container`: which container to run in (from `container_name`).
- `psql`: the Postgres command-line client. It is roughly the counterpart of `sqlcmd` for SQL Server.
- `-U gragas`: connect as user `gragas`.
- `-d gragas_db`: connect to database `gragas_db`.
- `< db/schema.sql` (Bash): feed the file to the command's input.
- `Get-Content db/schema.sql |` (PowerShell): read the file and pipe its contents into the command's input. Same effect.

`psql` executes the statements one after another, printing `CREATE EXTENSION`, `CREATE TYPE` and `CREATE TABLE` as each succeeds.

The script runs once on an empty database. Running it again fails because the types and tables already exist.

### 4. Look around in `psql`

```
docker exec -it gragas_db_container psql -U gragas -d gragas_db
```

- `-it`: `-i` as before, plus `-t`, which allocates a *terminal* so you can type interactively, with a prompt and line editing. Use `-it` when a person types and `-i` alone when a file is piped in.

You land at a prompt like `gragas_db=#`. Two kinds of input work here:

- **SQL**, ended with `;`. For example `SELECT count(*) FROM facts;`. Without the `;`, `psql` waits for more lines, and the prompt changes to `gragas_db-#`.
- **Meta-commands**, which start with a backslash and need no `;`. They are `psql` shortcuts, not SQL:

| Command | What it shows |
|---|---|
| `\dt` | list tables |
| `\d facts` | columns, types, keys and constraints of `facts` |
| `\dT+` | custom types, including the values of `fact_status` and `fact_kind` |
| `\dx` | installed extensions; `vector` should be there |
| `\x` | toggle expanded output, one column per line, for wide rows |
| `\?` | help for all meta-commands |
| `\q` | quit |

### Reset

```
docker compose down -v
```

- `down`: stop and **delete** the containers, and the network Compose created.
- `-v`: also delete the volumes, which means **all data in the database**. Without `-v`, the data survives and the next `up` reuses it.

Then repeat steps 2 and 3. A reset is the way to apply a new password from `.env`, or to rerun `db/schema.sql` from scratch.
