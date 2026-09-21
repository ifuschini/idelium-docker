FROM mariadb:13.0.2@sha256:d4fdec0510ad498e4f3127da30a99df3745bd6d5e611ae6ac5f76403d9284a8d

ARG STACK_SOURCE_REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/idelium/idelium-docker" \
      org.opencontainers.image.revision="${STACK_SOURCE_REVISION}"

COPY ideliumdb/sql/ /docker-entrypoint-initdb.d/
