# sakiladb/mariadb

A [MariaDB](https://mariadb.org/) Docker image preloaded with the
[Sakila](https://dev.mysql.com/doc/sakila/en/) sample database. One of the
[`sakiladb`](https://github.com/sakiladb) image family.

These images exist primarily as test fixtures for [`sq`](https://github.com/neilotoole/sq), a
command-line tool for querying SQL databases and structured data, but they are free for anyone to
use. MariaDB speaks the MySQL wire protocol, so `sq` connects with its
[MySQL driver](https://sq.io/docs/drivers/mysql).

Available on [Docker Hub](https://hub.docker.com/r/sakiladb/mariadb) and
[GitHub Container Registry](https://github.com/sakiladb/mariadb/pkgs/container/mariadb).

## Quick start

```shell
docker run -p 3306:3306 -d sakiladb/mariadb:latest
```

The Sakila data is baked into the image, so there is no initialization step at startup; the
container is ready in a few seconds.

The image declares a Docker
[`HEALTHCHECK`](https://docs.docker.com/reference/dockerfile/#healthcheck), so you can wait for
readiness rather than guessing. Its status becomes `healthy` once MariaDB is accepting connections:

```shell
docker run -p 3306:3306 -d --name sakila sakiladb/mariadb:latest
until [ "$(docker inspect -f '{{.State.Health.Status}}' sakila)" = healthy ]; do sleep 1; done
```

In Docker Compose, gate dependents with `depends_on: { condition: service_healthy }`. (MariaDB also
logs its native `ready for connections` line.)

## Connection

| Setting    | Value       |
|------------|-------------|
| host       | `localhost` |
| port       | `3306`      |
| database   | `sakila`    |
| user       | `sakila`    |
| password   | `p_ssW0rd`  |

Any MySQL/MariaDB client works with the settings above. For example, with
[`sq`](https://github.com/neilotoole/sq) ([install](https://sq.io/docs/install)). Note the
`mysql://` scheme, since MariaDB uses the MySQL protocol:

```shell
$ sq add 'mysql://sakila:p_ssW0rd@localhost:3306/sakila' --handle @sakila_maria
@sakila_maria  mysql  sakila@localhost:3306/sakila

$ sq '@sakila_maria.actor | .[0:5]'
actor_id  first_name  last_name     last_update
1         PENELOPE    GUINESS       2006-02-15T04:34:33Z
2         NICK        WAHLBERG      2006-02-15T04:34:33Z
3         ED          CHASE         2006-02-15T04:34:33Z
4         JENNIFER    DAVIS         2006-02-15T04:34:33Z
5         JOHNNY      LOLLOBRIGIDA  2006-02-15T04:34:33Z
```

## What's inside

The standard Sakila sample database: **16 tables and 7 views**, all owned by the `sakila` user.
It is loaded from the **same schema and data as [`sakiladb/mysql`](https://github.com/sakiladb/mysql)**
(the family's reference variant), so the object set, row counts, and data are identical.

[`sq inspect`](https://sq.io/docs/inspect) shows the whole schema (tables, views, row counts, and
columns) at a glance:

```shell
$ sq inspect @sakila_maria
SOURCE         DRIVER  NAME    FQ NAME     SIZE   TABLES  VIEWS  LOCATION
@sakila_maria  mysql   sakila  def.sakila  6.5MB  16      7      mysql://sakila:xxxxx@localhost:3306/sakila

NAME                        TYPE   ROWS   COLS
actor                       table  200    actor_id, first_name, last_name, last_update
address                     table  603    address_id, address, address2, district, city_id, postal_code, phone, last_update
category                    table  16     category_id, name, last_update
city                        table  600    city_id, city, country_id, last_update
country                     table  109    country_id, country, last_update
customer                    table  599    customer_id, store_id, first_name, last_name, email, address_id, active, create_date, last_update
film                        table  1000   film_id, title, description, release_year, language_id, original_language_id, rental_duration, rental_rate, length, replacement_cost, rating, special_features, last_update
film_actor                  table  5462   actor_id, film_id, last_update
film_category               table  1000   film_id, category_id, last_update
film_text                   table  1000   film_id, title, description
inventory                   table  4581   inventory_id, film_id, store_id, last_update
language                    table  6      language_id, name, last_update
payment                     table  16049  payment_id, customer_id, staff_id, rental_id, amount, payment_date, last_update
rental                      table  16044  rental_id, rental_date, inventory_id, customer_id, return_date, staff_id, last_update
staff                       table  2      staff_id, first_name, last_name, address_id, picture, email, store_id, active, username, password, last_update
store                       table  2      store_id, manager_staff_id, address_id, last_update
actor_info                  view   200    actor_id, first_name, last_name, film_info
customer_list               view   599    ID, name, address, zip code, phone, city, country, notes, SID
film_list                   view   997    FID, title, description, category, price, length, rating, actors
nicer_but_slower_film_list  view   997    FID, title, description, category, price, length, rating, actors
sales_by_film_category      view   16     category, total_sales
sales_by_store              view   2      store, manager, total_sales
staff_list                  view   2      ID, name, address, zip code, phone, city, country, SID
```

## Differences from other sakila variants

`sakiladb/mariadb` is built from the **same `1-sakila-schema.sql` / `2-sakila-data.sql` as
[`sakiladb/mysql`](https://github.com/sakiladb/mysql)** (the family's reference variant), byte for
byte. MariaDB runs that MySQL Sakila unmodified, so there is nothing to "port": the fixture shape,
row counts, and faithful data (including the restored Unicode accents in place names) are identical
to the MySQL image. Two engine-level notes:

- **`sq` uses its MySQL driver.** MariaDB speaks the MySQL wire protocol, so the connection scheme is
  `mysql://` and `sq inspect` reports `DRIVER: mysql`.
- **`address` has no `location` column.** Same as the MySQL reference: upstream MySQL Sakila ships a
  spatial `GEOMETRY` column there, which the reference removes so `address` is the same 8 columns
  across the whole family.

Like the MySQL image, `film_text` here is a real, **trigger-populated** table (kept in sync with
`film`).

## Available versions

Each MariaDB version is published as its own image tag. `latest` tracks the newest version
(currently 12).

| MariaDB | sakiladb Release | Architecture     | Docker Hub                       | GitHub Container Registry                |
|---------|------------------|------------------|----------------------------------|------------------------------------------|
| 12      | `v12.0.0`        | `amd64`, `arm64` | `sakiladb/mariadb:12`, `:latest` | `ghcr.io/sakiladb/mariadb:12`, `:latest` |
| 11      | `v11.0.0`        | `amd64`, `arm64` | `sakiladb/mariadb:11`            | `ghcr.io/sakiladb/mariadb:11`            |
| 10      | `v10.0.0`        | `amd64`, `arm64` | `sakiladb/mariadb:10`            | `ghcr.io/sakiladb/mariadb:10`            |

The tags follow MariaDB's bare-major scheme, and each moving major tracks the newest release in that
series: **`12`** is the newest line (gets `:latest`), **`11`** tracks the **11.8 LTS**, and **`10`**
tracks the **10.11 LTS** (the oldest line still in healthy support). All three publish `amd64` +
`arm64`.

**sakiladb Release** is the git tag the current image was built from (see
[releases](https://github.com/sakiladb/mariadb/releases)). The version is
`v{MARIADB_MAJOR}.{MINOR}.{PATCH}` with the **major** tracking MariaDB and the **minor**/**patch**
tracking sakiladb's own revisions (e.g. `v12.0.0` → `v12.0.1`).

Every version is published to both [Docker Hub](https://hub.docker.com/r/sakiladb/mariadb) and
[GitHub Container Registry](https://github.com/sakiladb/mariadb/pkgs/container/mariadb), and is
signed with [cosign](https://github.com/sigstore/cosign).

## Releasing a new version

Maintainers: releases are tag-driven. Pushing a semver tag `vN.x.y` builds and publishes that MariaDB
version; the version is derived from the tag, so there are no per-version branches. See
[CLAUDE.md](./CLAUDE.md) for the full, repeatable procedure.

## Changelog

### 2026-06-28

- **Initial release**: MariaDB `10`, `11`, `12`, each multi-arch (`amd64` + `arm64`), published to
  Docker Hub and GHCR and cosign-signed. The fixture is loaded from the same Sakila schema and data
  as `sakiladb/mysql` (16 tables + 7 views, faithful original data), and each image declares a Docker
  `HEALTHCHECK` (`mariadb-admin ping`).

## License

[BSD 3-Clause](./LICENSE).
