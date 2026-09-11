#!/usr/bin/env bash
set -euo pipefail

for script in start-idelium.sh scripts/*.sh; do
  bash -n "$script"
done

docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml config --quiet
docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.selenium.yml config --quiet
docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.selenium-cross-browser.yml config --quiet
docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.selenium.yml -f compose.runner.yml config --quiet
GO_API_IMAGE=idelium/api-go@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
WEB_IMAGE=idelium/web@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
GO_API_DB_PASSWORD=compose-validation-db-password \
DB_ROOT_PASSWORD=compose-validation-root-password \
  docker compose -f compose.go-cutover.yml config --quiet

if awk '/^FROM / && $2 !~ /@sha256:/ { print FILENAME ":" FNR ": unpinned base image"; failed=1 } END { exit failed }' \
  idelium-fe/Dockerfile ideliumapi/Dockerfile ideliumdb/Dockerfile idelium-cli/Dockerfile; then
  :
else
  exit 1
fi

if rg -n '(:latest|git clone|curl .*--insecure|curl .*-k\b|MYSQL_(ROOT_)?PASSWORD[=:][[:space:]]*[^$])' \
  Dockerfile docker-compose.yml compose.*.yml idelium-fe ideliumapi ideliumdb idelium-cli 2>/dev/null; then
  echo "Mutable sources, disabled TLS, or embedded database passwords were found." >&2
  exit 1
fi

for service in ideliumdb ideliumapi ideliumfe; do
  docker compose --env-file .env.example config | grep -q "  $service:"
done

docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.selenium.yml config | grep -q "  selenium-grid:"
docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.selenium-cross-browser.yml config | grep -q "  selenium-node-chromium:"
docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.selenium-cross-browser.yml config | grep -q "  selenium-node-firefox:"
docker compose --env-file .env.example -f docker-compose.yml -f compose.demo.yml -f compose.runner.yml --profile runner config | grep -q "  idelium-cli-runner:"

test "$(docker compose --env-file .env.example config | grep -c 'no-new-privileges:true')" -eq 4

test -f docs/ci/github-actions-idelium.yml
test -f docs/ci/gitlab-ci-idelium.yml
test -f docs/ci/README.md

grep -q 'actions/upload-artifact@v4' docs/ci/github-actions-idelium.yml
grep -q 'artifacts:' docs/ci/gitlab-ci-idelium.yml
grep -q 'junit:' docs/ci/gitlab-ci-idelium.yml
grep -q '^[[:space:]]*--junitReport=' docs/ci/github-actions-idelium.yml
grep -q '^[[:space:]]*--junitReport=' docs/ci/gitlab-ci-idelium.yml
grep -q '\[0-9a-f\]{40}' docs/ci/github-actions-idelium.yml
grep -q '\[0-9a-f\]{40}' docs/ci/gitlab-ci-idelium.yml

if rg -n '(:latest|--insecure|[[:space:]]-k\b|^[[:space:]]*IDELIUM_API_KEY:[[:space:]]*[^$[:space:]])' docs/ci; then
  echo "CI examples must pin dependencies, preserve TLS verification, and avoid embedded secrets." >&2
  exit 1
fi

grep -q 'Content-Security-Policy' idelium-fe/conf/httpd-vhosts-idelium-ssl.conf
grep -q 'X-Content-Type-Options' idelium-fe/conf/httpd-vhosts-idelium-ssl.conf
grep -q 'frame-ancestors' idelium-fe/conf/httpd-vhosts-idelium-ssl.conf

echo "Compose and shell validation passed."
