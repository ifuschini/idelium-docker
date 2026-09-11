# Go API cutover profile

The frontend already uses relative `/api/` URLs. The opt-in
`compose.go-cutover.yml` profile terminates TLS in Apache and forwards those
requests to the Go API, while the regular `docker-compose.yml` stack remains
the Laravel rollback target.

## Start the isolated profile

Use immutable image references and credentials supplied by the deployment
environment. Do not commit the values:

```sh
export GO_API_IMAGE=ghcr.io/idelium/idelium-api-go@sha256:<published-digest>
export WEB_IMAGE=ghcr.io/idelium/idelium-web@sha256:<published-digest>
export GO_API_DB_PASSWORD='<runtime-secret>'
export DB_ROOT_PASSWORD='<runtime-secret>'

docker compose -f compose.go-cutover.yml config
docker compose -f compose.go-cutover.yml up -d
```

The profile uses the existing Go-compatible database schema and waits for the
Go healthcheck before starting Apache. A browser request such as
`GET /api/health/live` is translated to the Go route `GET /health/live`; all
other public `/api/...` requests are mapped in the same way.

## Verify and roll back

```sh
curl --fail --silent --show-error \
  --cacert /path/to/deployed-ca.crt https://localhost/api/health/live
docker compose -f compose.go-cutover.yml ps
```

To roll back, stop only the opt-in profile and start the normal stack. The
normal Apache configuration routes `/api` to Laravel:

```sh
docker compose -f compose.go-cutover.yml down
docker compose up -d
```

The Go profile is intentionally not the default until a release has a real
published Go image digest, a migrated database, and a completed HTTP smoke
run. The profile does not delete the shared Laravel database volume.
