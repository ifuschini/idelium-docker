#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
case "$mode" in
  --demo)
    if [[ ! -f .env ]]; then
      cp .env.example .env
      echo "Created .env from .env.example."
    fi
    ./scripts/create-development-secrets.sh
    # The Go demo owns the public HTTPS port. Stop the legacy Laravel stack
    # first, but preserve its database and TLS volumes for rollback.
    docker compose -f docker-compose.yml -f compose.demo.yml down --remove-orphans
    export GO_API_DB_PASSWORD="$(<"${DB_PASSWORD_FILE:-./secrets/db_password}")"
    export DB_ROOT_PASSWORD="$(<"${DB_ROOT_PASSWORD_FILE:-./secrets/db_root_password}")"
    compose_files=(-f compose.go-demo.yml)
    build_flag=(--build)
    ;;
  --laravel-demo)
    ./scripts/create-development-secrets.sh
    compose_files=(-f docker-compose.yml -f compose.demo.yml)
    build_flag=(--build)
    ;;
  --production)
    compose_files=(-f docker-compose.yml -f compose.production.yml)
    build_flag=(--build)
    ;;
  --release)
    compose_files=(-f docker-compose.yml -f compose.production.yml -f compose.release.yml)
    build_flag=(--no-build)
    ;;
  *)
    echo "Usage: $0 --demo | --laravel-demo | --production | --release" >&2
    exit 2
    ;;
esac

if [[ "$mode" != "--release" ]]; then
  export API_SOURCE_REVISION=${API_SOURCE_REVISION:-$(git -C ../idelium-api rev-parse HEAD)}
  export WEB_SOURCE_REVISION=${WEB_SOURCE_REVISION:-$(git -C ../idelium-web rev-parse HEAD)}
  export STACK_SOURCE_REVISION=${STACK_SOURCE_REVISION:-$(git rev-parse HEAD)}
  export IDELIUM_VERSION=${IDELIUM_VERSION:-${STACK_SOURCE_REVISION:0:12}}
fi

echo "Starting Idelium in ${mode#--} mode and waiting for health checks."
if ! docker compose "${compose_files[@]}" up "${build_flag[@]}" --detach --wait --wait-timeout "${IDELIUM_START_TIMEOUT:-300}"; then
    echo "Idelium did not become ready. Inspecting service state and recent logs." >&2
    docker compose "${compose_files[@]}" ps >&2 || true
    docker compose "${compose_files[@]}" logs --tail=100 >&2 || true
    exit 1
fi

./scripts/smoke-test.sh "${compose_files[@]}"
echo "Idelium is ready at https://localhost:${HTTPS_PORT:-443}."
