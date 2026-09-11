#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

missing=()
for repository in ../idelium-api ../idelium-web; do
  if [[ ! -d "$repository/.git" ]]; then
    missing+=("$repository")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Missing required sibling repositories:" >&2
  printf '  %s\n' "${missing[@]}" >&2
  echo "Clone idelium-api, idelium-web, and idelium-docker beside each other." >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not available in PATH. Install or start Docker Desktop first." >&2
  exit 2
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is not available. Update Docker Desktop or Docker Engine." >&2
  exit 2
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example."
fi

umask 077
mkdir -p secrets
printf 'admin@idelium.org' > secrets/admin_email
printf 'admin' > secrets/admin_password
echo "Configured local demo credentials in the ignored secrets directory."

./start-idelium.sh --demo

https_port="$(grep -E '^HTTPS_PORT=' .env | tail -n 1 | cut -d= -f2-)"
https_port="${https_port:-443}"
if [[ "$https_port" == "443" ]]; then
  url="https://localhost"
else
  url="https://localhost:${https_port}"
fi

echo
echo "Idelium demo is ready."
echo "Open: $url"
echo
echo "The Go-only demo uses synthetic smoke fixtures. Inspect the ignored"
echo "secrets directory only when local credentials are needed."
echo
echo "Stop the demo with:"
echo "  docker compose -f compose.go-demo.yml down"
