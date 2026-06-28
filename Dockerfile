# check=skip=SecretsUsedInArgOrEnv
# ^ The *_PASSWORD values below are the public, documented Sakila fixture
#   credential (p_ssW0rd): these are throwaway test-fixture images with a
#   fixed, published password, not a secret. This lint rule is skipped.

# MariaDB version to build. The CI release workflow overrides this per release,
# deriving it from the git tag (e.g. v12.0.0 -> 12, v11.0.0 -> 11, v10.0.0 -> 10).
# The default is the newest version, for convenient local `docker build`.
ARG MARIADB_VERSION=12

FROM mariadb:${MARIADB_VERSION} AS builder
ENV MARIADB_ROOT_PASSWORD=p_ssW0rd
ENV MARIADB_DATABASE=sakila
ENV MARIADB_USER=sakila
ENV MARIADB_PASSWORD=p_ssW0rd

COPY ./1-sakila-schema.sql /docker-entrypoint-initdb.d/step_1.sql
COPY ./2-sakila-data.sql /docker-entrypoint-initdb.d/step_2.sql
COPY ./3-sakila-complete.sql /docker-entrypoint-initdb.d/step_3.sql

# Neuter the entrypoint's `exec "$@"` so it initializes the database into
# /var/lib/mysql and then exits, instead of staying up as a server.
# https://serverfault.com/questions/930141/creating-a-mysql-image-with-the-db-preloaded
# https://serverfault.com/questions/796762/creating-a-docker-mysql-container-with-a-prepared-database-scheme
RUN ["sed", "-i", "s/exec \"$@\"/echo \"skipping...\"/", "/usr/local/bin/docker-entrypoint.sh"]

USER mysql
RUN ["/usr/local/bin/docker-entrypoint.sh", "mariadbd"]

FROM mariadb:${MARIADB_VERSION}
ENV MARIADB_ROOT_PASSWORD=p_ssW0rd
ENV MARIADB_DATABASE=sakila
ENV MARIADB_USER=sakila
ENV MARIADB_PASSWORD=p_ssW0rd

# Copy the populated data dir from the builder stage; the published image ships
# with Sakila already loaded, so there is no init cost at container start.
COPY --from=builder /var/lib/mysql /data
RUN rm -rf /var/lib/mysql/*
RUN mv /data/* /var/lib/mysql/

USER mysql

# Readiness probe: the container reports `healthy` once MariaDB is accepting TCP
# connections. mariadb-admin can emit a password-on-CLI warning to stderr
# (harmless); discard it and normalize any failure to exit 1. (MariaDB 12 drops
# the legacy `mysqladmin` symlink, so the canonical `mariadb-admin` is used.)
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
  CMD mariadb-admin ping -h 127.0.0.1 -u sakila -pp_ssW0rd --silent 2>/dev/null || exit 1

# See: https://dev.to/mdemblani/docker-container-uncaught-kill-signal-10l6
COPY ./signal-listener.sh /sakila/run.sh
# Entrypoint overload to catch the ctrl+c and stop signals
ENTRYPOINT ["/bin/bash", "/sakila/run.sh"]
