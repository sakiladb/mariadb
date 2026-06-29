# CLAUDE.md

Maintainer guide for **`sakiladb/mariadb`**, a MariaDB Docker image preloaded with the
[Sakila](https://dev.mysql.com/doc/sakila/en/) sample database, published to
[Docker Hub](https://hub.docker.com/r/sakiladb/mariadb) and
[GitHub Container Registry](https://github.com/sakiladb/mariadb/pkgs/container/mariadb).

> One of the [`sakiladb`](https://github.com/sakiladb) image family (`postgres`, `mysql`, `mariadb`,
> `sqlserver`, `oracle`, `clickhouse`, `rqlite`). The release machinery in
> [How releases work](#how-releases-work) is **shared across the family** (the reference template
> lives in [`sakiladb/postgres`](https://github.com/sakiladb/postgres)); the build details in
> [How the image is built](#how-the-image-is-built) are **MariaDB-specific**. The org-level landing
> page ([github.com/sakiladb](https://github.com/sakiladb)) is rendered from the
> [`sakiladb/.github`](https://github.com/sakiladb/.github) repo (`profile/README.md`); edit it there
> to change the family overview.

## Purpose

These images exist primarily as **test fixtures for the [`sq`](https://github.com/neilotoole/sq) CLI**.
`sq`'s suite runs against every variant and asserts a uniform Sakila schema, so each image must
expose the **same object set: 16 tables + 7 views**. Treat that as a hard consistency contract.

`sq` talks to MariaDB through its **MySQL driver** (MariaDB speaks the MySQL wire protocol), so there
is no separate "mariadb" driver in `sq`; the connection scheme is `mysql://` and `sq inspect` reports
`DRIVER: mysql`. A schema change here is therefore the same cross-repo concern as for `sakiladb/mysql`:
`sq`'s expectations (`testh/sakila/sakila.go`, `libsq/driver/driver_test.go`, `cli/cmd_inspect_test.go`)
must be kept in lockstep.

## The dataset

The standard Sakila database, preloaded and owned by the `sakila` user: **16 tables + 7 views**.

**The schema and data are shared verbatim with [`sakiladb/mysql`](https://github.com/sakiladb/mysql)**,
the family's reference variant. `1-sakila-schema.sql` and `2-sakila-data.sql` are **byte-identical
copies** of the MySQL repo's files (MariaDB runs the MySQL Sakila unmodified). This is the most
important maintenance fact for this repo:

> **Keep the SQL in lockstep with `sakiladb/mysql`.** When the reference schema or data changes there
> (a faithfulness fix, a column trim, a view-determinism tweak), copy the updated
> `1-sakila-schema.sql` / `2-sakila-data.sql` here verbatim and re-release. Do **not** hand-edit them
> in isolation; they are intentionally identical so the two images stay in parity.

Inherited from the reference:

- **`address` has no `location` column.** Upstream MySQL Sakila ships a spatial `GEOMETRY` column
  there; the reference removes it so `address` is 8 columns across the whole family.
- **`film_text` is a real, trigger-populated table** (the `INSERT`/`UPDATE`/`DELETE` triggers in
  `1-sakila-schema.sql` keep it in sync with `film`).
- **Faithful data**, including the restored Unicode accents in international place names
  (`Réunion`, `A Coruña`, ...), verified present on MariaDB.

One thing worth checking when the data changes: MariaDB's default `utf8mb4` collation differs from
MySQL 8's (`utf8mb4_uca1400_ai_ci` vs `utf8mb4_0900_ai_ci`), which can affect the ordering of
accented values inside the aggregating views. The views sort deterministically by value, and ASCII
ordering matches, but **byte-identical view output for accented rows across the whole family is the
job of the cross-engine parity guard** ([neilotoole/sq#963](https://github.com/neilotoole/sq/issues/963)).

## How the image is built

*(MariaDB-specific.)* `Dockerfile` is a two-stage build that bakes the data into the image so there is
no initialization cost at container start. The base-image version is parameterized by an
`ARG MARIADB_VERSION` (default = newest), which the release workflow sets per build:

1. **`builder` stage**: `FROM mariadb:${MARIADB_VERSION}`, copies the three SQL files into
   `/docker-entrypoint-initdb.d/`, neuters the entrypoint's `exec "$@"` (so the server does not stay
   running), then runs the entrypoint once (`docker-entrypoint.sh mariadbd`) to initialize the
   database into `/var/lib/mysql`.
2. **final stage**: `FROM mariadb:${MARIADB_VERSION}` again, copies the populated `/var/lib/mysql`
   from the builder stage. The published image ships with Sakila already loaded.

The three init SQL files run in order (the stock MariaDB entrypoint runs `/docker-entrypoint-initdb.d/`,
then creates the `sakila` user/db from the `MARIADB_*` env):

| File | Role |
|------|------|
| `1-sakila-schema.sql` | Schema: tables (incl. `film_text` + its triggers), views, indexes. |
| `2-sakila-data.sql` | Data (multi-row `INSERT` statements). |
| `3-sakila-complete.sql` | Grant `ALL PRIVILEGES` to `sakila`; log the completion message. |

> **MariaDB binary names.** This image uses the canonical `mariadbd` (daemon) and `mariadb-admin`
> (healthcheck), **not** the legacy `mysqld` / `mysqladmin` symlinks. MariaDB **12 removed those
> compat symlinks**, so using the `mysql*` names would break on `:12`. `mariadbd` / `mariadb-admin`
> exist on all published lines (10, 11, 12).

> **Env vars.** Uses the native `MARIADB_ROOT_PASSWORD` / `MARIADB_DATABASE` / `MARIADB_USER` /
> `MARIADB_PASSWORD` (the MariaDB image also accepts the `MYSQL_*` spellings, but the native ones are
> preferred here).

> **Entrypoint quirk:** the final stage overrides the entrypoint with `signal-listener.sh`, a wrapper
> that traps `SIGINT`/`SIGTERM` and forwards them to `mariadbd` (so `Ctrl+C` / `docker stop` shut
> down cleanly). It still launches the stock `docker-entrypoint.sh mariadbd`, so MariaDB starts
> normally against the pre-baked data dir. (Same pattern as `sakiladb/mysql`, with the daemon renamed.)

### Readiness (HEALTHCHECK)

The final stage declares a Docker `HEALTHCHECK` (`mariadb-admin ping … --silent`), so the container
reports `healthy` once MariaDB accepts TCP connections (the local build reaches `healthy` in a few
seconds). It connects over TCP (`-h 127.0.0.1`) as the `sakila` user; `mariadb-admin` can emit a
password-on-CLI warning to stderr, which the check discards, normalizing any failure to exit `1`.

> **Family convention:** every `sakiladb` image declares a `HEALTHCHECK` using its engine's native
> readiness probe (`pg_isready`, `mysqladmin ping`, `mariadb-admin ping`, `sqlcmd … SELECT 1`,
> `healthcheck.sh SAKILA`, …). The probe command differs per engine; the readiness *contract*
> (`healthy` = ready to serve) is uniform.

## How releases work

*(Shared across the `sakiladb` family.)*

Releases are **tag-driven**. There is a single long-lived branch, `master`, and **pushing a semver
tag `vN.x.y` publishes that MariaDB version**. The version is read from the tag name, so the tag is
the sole source of truth for what gets built; there are **no per-version branches**.

- `.github/workflows/docker-publish.yml` builds on every push / PR / tag, but **only pushes to a
  registry on `v*.*.*` tags**. Branch pushes, PRs, and manual `workflow_dispatch` runs are build-only
  smoke tests. (Registry-login steps are gated on `IS_RELEASE`, so PR / Dependabot builds with no
  secrets stay green.)
- The **"Determine MariaDB version" step** computes a *version label* that is both the published
  Docker tag and the `mariadb:<label>` base image. MariaDB's published lines are bare majors, so the
  mapping is simple:

  | Git tag | Label | Base image | Resolves to | Arch |
  |---------|-------|-----------|-------------|------|
  | `v10.0.x` | `10` | `mariadb:10` | **10.11 LTS** | amd64 + arm64 |
  | `v11.0.x` | `11` | `mariadb:11` | **11.8 LTS** | amd64 + arm64 |
  | `v12.0.x` | `12` | `mariadb:12` | newest 12.x | amd64 + arm64 |

  The label is the tag's major (`v12.0.0` → `12`). The step validates the label is digits with at most
  one dot (a dotted minor like `11.4` is allowed for manual smoke-test builds only). Unlike
  `sakiladb/mysql` (whose `5.6`/`5.7` lines are amd64-only), every MariaDB line publishes both arches,
  so the `platforms` output is constant.
- The tag produces the Docker tag **`{{label}}`** (`v12.0.0` → `12`), pushed to **both Docker Hub and
  GHCR**, and **cosign-signed**.

### The `latest` tag

`latest` must always point at the **newest** version. The workflow never auto-assigns it
(`flavor: latest=false`); it emits `latest` **only when the tag's label equals the `LATEST_VERSION`
env var** in the workflow (currently `12`). Because `latest` is gated on a fixed value rather than
push order, **tag-push order is irrelevant** and republishing an older version can never steal
`latest`.

### Recipe: release a new major version (e.g. MariaDB 13)

```bash
git switch master && git pull
# 1. In .github/workflows/docker-publish.yml, bump:  LATEST_VERSION: "13"
# 2. (Optional) bump the Dockerfile's `ARG MARIADB_VERSION=13` default, for local builds.
git commit -am "mariadb 13 is now the newest"
git push origin master                       # build-only smoke test (builds mariadb:13 via the new default)

# 3. Tag to publish `13` + `latest` (Docker Hub + GHCR):
git tag v13.0.0 && git push origin v13.0.0
```

The previous newest stops getting `latest` automatically, because `latest` keys off `LATEST_VERSION`.

### Recipe: republish or build any version (e.g. rebuild MariaDB 11)

No branch needed; just tag `master`. If `v11.0.0` already exists, bump to the next **unused** patch
(`git tag -l 'v11.*'` first).

```bash
git switch master && git pull
git tag v11.0.1 && git push origin v11.0.1   # builds & publishes `11`; `latest` untouched (11 ≠ LATEST_VERSION)
```

To preview an arbitrary version's build **without** publishing, run the workflow manually
(GitHub ▸ Actions ▸ Docker ▸ Run workflow ▸ `mariadb_version = 11`), or build locally:
`docker build --build-arg MARIADB_VERSION=11 .`.

After any release:

1. **Verify the published artifact**: pull the image, confirm the schema (`16 tables + 7 views`,
   `address` = 8 columns) and the MariaDB version, and confirm `latest` still points at the newest.
2. **Update the README "Available versions" table**: it is maintained by hand. Set the row's
   **sakiladb Release** cell to the new tag; when the newest version changes, move the `:latest`
   annotation. Add a dated **Changelog** entry if the change is user-visible.

## Conventions

- **Credentials:** database / user / password = `sakila` / `sakila` / `p_ssW0rd`.
- **Tags:** Docker tag is the MariaDB major (`10`, `11`, `12`); `latest` on the newest. Git tags are
  `vN.x.y`: the **major** is the MariaDB major and `.x.y` is sakiladb's own revision (so `v12.0.0` →
  `v12.0.1`).
- **No AI attribution** in commits, tags, PRs, or any other content.
