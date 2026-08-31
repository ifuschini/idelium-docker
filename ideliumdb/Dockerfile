FROM mariadb:12.3.3@sha256:dd9b303aed4f4890ed09f766d8ca9ddfd176c0c6f6267feff53b3192ec65a979

ARG STACK_SOURCE_REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/idelium/idelium-docker" \
      org.opencontainers.image.revision="${STACK_SOURCE_REVISION}"

COPY ideliumdb/sql/ /docker-entrypoint-initdb.d/
