<picture>
  <source media="(prefers-color-scheme: dark)" srcset="logo/idelium_white.png">
  <img alt="Idelium" src="logo/idelium.png">
</picture>

# Idelium Docker stack

This repository provides the reproducible container build and Compose topology
for Idelium API, Idelium Web, and MariaDB. It supports an explicit local demo,
a production-oriented local build, and deployment from immutable published
images.

The stack builds application sources from adjacent, fixed Git checkouts. It does
not clone a moving branch during a build, use `latest` images, embed credentials,
or expose the database and API directly to the host.

## Product and enterprise planning

- [Enterprise console walkthrough](idelium-console-walkthrough-enterprise.md)
  explains the current product model, console flows, repository assessment, and
  enterprise-readiness gaps.
- [Enterprise roadmap](docs/enterprise-roadmap.md) converts that walkthrough
  into release phases, epics, implementation tickets, acceptance criteria, and
  enterprise-ready gates.

## Services

```text
Browser / Idelium CLI
          │
          │ HTTPS :443
          ▼
     ideliumfe
  Apache + Vue SPA
          │ /api reverse proxy
          ▼
     ideliumapi ───────── queue worker
  Apache + Laravel
          │
          ▼
     ideliumdb
       MariaDB

ideliuminit runs migrations and explicitly enabled seeds before the API starts.
```

| Service | Role | Host exposure |
| --- | --- | --- |
| `ideliumdb` | Persistent MariaDB database | internal only |
| `ideliuminit` | One-shot migrations and optional seed data | none |
| `ideliumapi` | Laravel API and managed queue worker | internal only |
| `ideliumfe` | Vue static site, HTTPS termination, and API reverse proxy | HTTPS only |

Startup dependencies are health-aware: the database must be healthy,
initialization must complete successfully, the API must pass its health check,
and then the frontend becomes ready.

## Pinned build inputs

The Dockerfiles pin base images by digest:

- MariaDB 10.6.22.
- PHP 8.4.13 on Apache Bookworm.
- Composer 2.10.2.
- Node.js 22.17.0 on Bookworm Slim.
- Apache HTTP Server 2.4.65 on Bookworm.

API dependencies come from `composer.lock`; frontend dependencies come from
`package-lock.json`. Images receive OCI source-revision labels so a built
artifact can be traced to its API, Web, and stack commits.

## Requirements

- Docker Engine or Docker Desktop with Docker Compose v2.
- Git.
- Bash.
- OpenSSL for development-secret generation.
- Available host port 443, or another port configured with `HTTPS_PORT`.
- Sufficient memory and disk for three images, MariaDB, and dependency builds.

For local builds, the repositories must be sibling directories:

```text
workspace/
├── idelium-api/
├── idelium-docker/
└── idelium-web/
```

## Quick start: demo

Clone all three repositories beside each other, then enter this repository:

```bash
git clone https://github.com/idelium/idelium-api.git
git clone https://github.com/idelium/idelium-web.git
git clone https://github.com/idelium/idelium-docker.git
cd idelium-docker
./start-idelium.sh --demo
```

For a guided local demo startup, use the convenience wrapper instead:

```bash
./quickstart-demo.sh
```

The wrapper verifies the required sibling repositories, creates `.env` from
`.env.example` when needed, configures the local demo administrator as
`admin@idelium.org` / `admin`, starts demo mode, and prints the local URL.

Demo startup automatically creates `.env` from `.env.example` when it is
missing, then:

1. creates missing random development secrets under the ignored `secrets/`
   directory with restrictive permissions;
2. builds the database, API, and frontend images from the checked-out sources;
3. starts MariaDB and waits for it to become healthy;
4. runs migrations, base seeds, and demo seeds once;
5. starts the API and frontend after their dependencies pass;
6. performs a verified HTTPS request through the frontend reverse proxy.

Open [https://localhost](https://localhost). Demo mode generates a short-lived
self-signed certificate, so the browser will not trust it automatically.

The generated demo identity is stored in `secrets/demo_email` and
`secrets/demo_password`. The demo administrator defaults to
`admin@idelium.org` / `admin` and is stored in `secrets/admin_email` and
`secrets/admin_password`. Copy secrets using a secure local method. They are
never committed and must never be pasted into logs, screenshots, issues, or chat
transcripts. These defaults are for local demo mode only and must not be used in
production.

### Stop or reset the demo

Stop containers while preserving database and certificate volumes:

```bash
docker compose -f docker-compose.yml -f compose.demo.yml down
```

To destroy the demo database and generated certificate volume as well:

```bash
docker compose -f docker-compose.yml -f compose.demo.yml down --volumes
```

Removing volumes is destructive. The ignored secret files remain on disk until
you intentionally remove or rotate them.

## Startup modes

The wrapper requires exactly one mode so development behavior cannot be enabled
implicitly:

| Command | Source | TLS | Seeds | Build behavior |
| --- | --- | --- | --- | --- |
| `./start-idelium.sh --demo` | adjacent repos | generated self-signed certificate | base + demo | local build |
| `./start-idelium.sh --production` | adjacent repos | mounted trusted certificate | disabled | local build |
| `./start-idelium.sh --release` | published images | mounted trusted certificate | disabled | pull, never build |

All modes wait for health checks and then run the HTTPS smoke test. Override the
default 300-second readiness limit with `IDELIUM_START_TIMEOUT` when a slow build
host needs more time.

## Configuration

Copy `.env.example` to `.env` and change only the values appropriate to the
target environment. `.env` contains non-secret configuration and paths to secret
files; secret values belong in ignored files or a deployment secret provider.

### General values

| Variable | Purpose | Default |
| --- | --- | --- |
| `IDELIUM_VERSION` | Local image tag | `local` |
| `APP_ENV` | Laravel runtime environment | `production` |
| `APP_URL` | Public application origin | `https://localhost` |
| `CORS_ALLOWED_ORIGINS` | Comma-separated trusted browser origins for API requests | `https://localhost,http://localhost:5173,http://127.0.0.1:5173` |
| `SANCTUM_STATEFUL_DOMAINS` | Comma-separated hosts treated as first-party by Laravel Sanctum | `localhost,localhost:5173,127.0.0.1,127.0.0.1:5173` |
| `HTTPS_PORT` | Host port mapped to frontend HTTPS | `443` |
| `DB_DATABASE` | MariaDB database name | `ideliumdb` |
| `DB_USERNAME` | MariaDB application account | `idelium` |
| `TLS_MODE` | Frontend certificate policy | `production` |
| `TLS_COMMON_NAME` | Development certificate common name | `localhost` |
| `TLS_CERT_DIR` | Production directory containing certificate and key | `./certs` |
| `IDELIUM_LAUNCHER_CA_BUNDLE` | Read-only in-container PEM bundle for a private remote-launcher CA | system trust store |
| `IDELIUM_LAUNCHER_CONNECT_TIMEOUT` | Remote-launcher connection timeout in seconds | `5` |
| `IDELIUM_LAUNCHER_TIMEOUT` | Remote-launcher response timeout in seconds | `30` |

Remote launcher endpoints must use HTTPS. The API verifies certificate chains
and hostnames and never enables its development-only insecure mode through the
supported Docker stack. For a private CA, mount the public CA bundle read-only
into both API services and set `IDELIUM_LAUNCHER_CA_BUNDLE` to the same
in-container path. Legacy `http://` platform endpoints must be migrated before
launching tests.

### Secret file paths

| Variable | Expected content |
| --- | --- |
| `DB_PASSWORD_FILE` | MariaDB application-account password |
| `DB_ROOT_PASSWORD_FILE` | MariaDB root password |
| `APP_KEY_FILE` | Laravel key in `base64:...` format |
| `DEMO_EMAIL_FILE` / `DEMO_PASSWORD_FILE` | Demo identity, demo mode only |
| `ADMIN_EMAIL_FILE` / `ADMIN_PASSWORD_FILE` | Seeded administrator, demo mode only |

Secret files are mounted under `/run/secrets` and read at runtime. Create them
with owner-only permissions. Never put the secret value directly in a Compose
file, Dockerfile, image build argument, tracked `.env`, or shell command that is
recorded in history.

### Testing Idelium Web through Vite

When developing `idelium-web` with Vite, keep the Docker backend running and set
the web repository `.env` to call the Docker API:

```env
VITE_IDELIUM_API_BASE_URL=https://localhost/api/
```

The Docker stack allows `http://localhost:5173` and `http://127.0.0.1:5173` by
default for local browser requests with Sanctum cookies. Restart the API
container after changing `CORS_ALLOWED_ORIGINS` or `SANCTUM_STATEFUL_DOMAINS`.

### Importing JSON tests from the web console

Idelium supports a native JSON import format for creating a test and its
reusable steps from the web console. To smoke-test the public demo page, upload
[`docs/examples/idelium-demo-test-import.json`](docs/examples/idelium-demo-test-import.json)
from **Tests > Import Idelium JSON**. The full format and UI procedure are
documented in
[`docs/importing-idelium-json-tests.md`](docs/importing-idelium-json-tests.md).

### Optional Selenium Grid and CLI runner profiles

The base stack runs the Idelium portal, API, and database. Browser execution is
performed by `idelium-cli`, so Selenium infrastructure is intentionally optional.
For local Selenium Grid testing, start the stack with the pinned Chromium Grid
profile:

```bash
docker compose -f docker-compose.yml -f compose.demo.yml -f compose.selenium.yml up -d
```

The Grid is exposed on `http://localhost:4444` by default. Configure an Idelium
environment or CLI override with:

```json
{
  "browser": "chrome",
  "seleniumGridUrl": "http://localhost:4444",
  "seleniumGridCapabilities": {
    "platformName": "linux",
    "se:name": "Idelium Selenium Grid test"
  }
}
```

When the CLI runs from another container on the Compose network, use
`http://selenium-grid:4444` instead of `http://localhost:4444`. Change the host
port with `SELENIUM_GRID_PORT` if port `4444` is already in use.

Run a WebDriver smoke test against the optional Grid profile with:

```bash
./scripts/selenium-grid-smoke-test.sh \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium.yml
```

The smoke test creates a real Chrome WebDriver session through Grid, opens a
small local data page, verifies the page title, and closes the session. It does
not require Idelium credentials.

### CI/CD integration examples

Pinned GitHub Actions and GitLab CI examples are available under
[`docs/ci/`](docs/ci/). They validate immutable component revisions, start the
stack, run Idelium CLI non-interactively, preserve CLI exit codes, and publish
JSON, HTML, Markdown, and JUnit reports as CI artifacts without printing API
keys.

For CI-grade cross-browser coverage, use the pinned Selenium Hub profile with
Chromium and Firefox nodes:

```bash
docker compose \
  --project-name idelium-selenium-cross-browser \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium-cross-browser.yml \
  up -d --wait selenium-grid selenium-node-chromium selenium-node-firefox

./scripts/selenium-cross-browser-smoke-test.sh

docker compose \
  --project-name idelium-selenium-cross-browser \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium-cross-browser.yml \
  down --volumes --remove-orphans
```

The cross-browser smoke test runs the same representative WebDriver flow on
Chrome-compatible Chromium and Firefox nodes, redacts WebDriver session ids from
failure diagnostics, and closes every session before exiting. The pinned image
set is `selenium/hub:4.27.0-20241204`,
`selenium/node-chromium:4.27.0-20241204`, and
`selenium/node-firefox:4.27.0-20241204`. Add Edge-compatible coverage by
introducing a pinned Selenium Edge node in a separate reviewed overlay when the
CI runner can support that browser image reliably.

When you want the Idelium CLI inside the same Compose network as the API and
Grid, add the optional runner overlay:

```bash
docker compose \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium.yml \
  -f compose.runner.yml \
  --profile runner \
  run --rm idelium-cli-runner idelium --help
```

The runner image is built from the adjacent `idelium-cli` checkout and records
the CLI and stack revisions as OCI labels. If a run needs an Idelium API key,
write it to an ignored local file and mount it only for that run:

```bash
docker compose \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium.yml \
  -f compose.runner.yml \
  --profile runner \
  run --rm \
  --volume ./secrets/idelium_cli_api_key:/run/secrets/idelium_cli_api_key:ro \
  idelium-cli-runner idelium --help
```

When `/run/secrets/idelium_cli_api_key` is mounted, the container copies it to
the CLI's protected `~/.idelium` file at runtime. Do not pass API keys in the
Compose file, image build arguments, command line, logs, or screenshots.

Example in-network execution values:

```bash
docker compose \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium.yml \
  -f compose.runner.yml \
  --profile runner \
  run --rm idelium-cli-runner \
  idelium \
    --idProject=1 \
    --idCycle=1 \
    --environment=local \
    --ideliumwsBaseurl=https://ideliumfe \
    --seleniumGridUrl=http://selenium-grid:4444
```

Use project, cycle, and environment names from your own Idelium instance. The
frontend container's development certificate is trusted by the browser only on
the host; configure an appropriate CA bundle for non-demo runner workflows.

### Appium 2 integration

Appium execution is intentionally external to the base Docker stack because
mobile infrastructure depends on host operating systems, SDKs, physical devices,
emulators, simulators, signing configuration, or device-farm providers. Use the
dedicated [Appium 2 integration guide](docs/appium-integration.md) for supported
topologies, UiAutomator2/XCUITest examples, cloud provider placeholders, and
troubleshooting guidance.

### Image and revision values

`API_IMAGE`, `WEB_IMAGE`, and `DB_IMAGE` select local image repositories.
`API_SOURCE_REVISION`, `WEB_SOURCE_REVISION`, and `STACK_SOURCE_REVISION` are
normally derived automatically and recorded as image labels. Do not set false
revision values to make a build appear reproducible.

## Production-oriented local build

Production mode requires all secret files and a trusted TLS certificate before
startup. The certificate directory must contain:

```text
server.crt
server.key
```

The certificate must cover the hostname in `APP_URL`, include the required
intermediate chain, and have a protected private key. Configure `.env`, create
the secret files through your secure provider, and run:

```bash
./start-idelium.sh --production
```

Production mode fails if the certificate mount is absent. It does not generate
a self-signed certificate and does not run demo or base seeders. Migrations still
run through the one-shot initialization service before the API starts.

Before a real deployment, review [Stack operations](docs/operations.md) for
certificate rotation, secret rotation, privilege boundaries, backup, and
rollback requirements.

## Reproducible local images

The dedicated build wrapper requires clean API, Web, and stack worktrees. Commit
the intended revisions first, then run:

```bash
./scripts/build-local.sh --no-cache
```

The script:

- refuses uncommitted source changes;
- derives exact revisions from all three repositories;
- tags every image with the stack version;
- builds only from adjacent local contexts and committed lockfiles;
- verifies the OCI revision labels after the build.

For a normal cached rebuild of the same revisions:

```bash
./scripts/build-local.sh
```

Use a no-cache build whenever Dockerfile instructions, base images, system
packages, entrypoints, or dependency-installation behavior changes.

## Published release images

Release mode is deliberately separate from local builds. Set complete immutable
image references—preferably registry references with digests—in:

- `API_RELEASE_IMAGE`
- `WEB_RELEASE_IMAGE`
- `DB_RELEASE_IMAGE`

Then pull and start them:

```bash
docker compose \
  -f docker-compose.yml \
  -f compose.production.yml \
  -f compose.release.yml \
  pull
./start-idelium.sh --release
```

The release overlay applies `pull_policy: always`; startup uses `--no-build` and
cannot silently substitute local application sources for the published images.
Record all three image references together as one release unit.

## Data persistence and initialization

MariaDB data is stored in the named `ideliumdb_data` volume. The `ideliuminit`
service waits for database health, runs migrations, and executes only seed sets
explicitly enabled by the selected overlay. Its successful completion is a hard
dependency of the API.

If initialization fails, the API intentionally remains stopped. Correct the
underlying migration, secret, or database problem, then recreate the
initialization/API services. Do not bypass the dependency or mark a failed
migration as successful manually.

Back up the database before releases that include schema changes. Migrations
must remain compatible with the previous application release during a rolling
transition or include an explicit maintenance and rollback plan.

## Health checks and smoke tests

Readiness covers the actual dependency chain:

- MariaDB answers an authenticated health query.
- API initialization exits successfully.
- The API serves the Sanctum CSRF endpoint and can inspect migration status.
- The frontend serves HTTPS with its configured certificate.
- The smoke test reaches the API through the public frontend proxy while
  verifying that certificate.

Inspect state and recent logs with the correct overlay:

```bash
docker compose -f docker-compose.yml -f compose.demo.yml ps
docker compose -f docker-compose.yml -f compose.demo.yml logs --tail=100 ideliuminit
docker compose -f docker-compose.yml -f compose.demo.yml logs --tail=100 ideliumapi
docker compose -f docker-compose.yml -f compose.demo.yml logs --tail=100 ideliumfe
```

Run the smoke test independently:

```bash
./scripts/smoke-test.sh -f docker-compose.yml -f compose.demo.yml
```

Replace `compose.demo.yml` with `compose.production.yml` for production mode.
Review output before sharing it and redact customer data, credentials, cookies,
authorization headers, and protected response content.

Run the optional Selenium Grid smoke test independently:

```bash
./scripts/selenium-grid-smoke-test.sh \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium.yml
```

Run the pinned cross-browser WebDriver smoke test independently:

```bash
docker compose \
  --project-name idelium-selenium-cross-browser \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium-cross-browser.yml \
  up -d --wait selenium-grid selenium-node-chromium selenium-node-firefox

./scripts/selenium-cross-browser-smoke-test.sh

docker compose \
  --project-name idelium-selenium-cross-browser \
  -f docker-compose.yml \
  -f compose.demo.yml \
  -f compose.selenium-cross-browser.yml \
  down --volumes --remove-orphans
```

## Security model

- Only the frontend HTTPS port is published to the host.
- API and database traffic stays on the internal Compose bridge network.
- Every service uses Docker's `no-new-privileges` restriction and an init
  process for signal handling and zombie reaping.
- MariaDB and Apache keep only the startup privileges needed to initialize
  storage, bind ports, and switch to their worker identities.
- Secrets are mounted as files and excluded from image layers and source.
- Production requires trusted TLS; demo TLS is explicit and local-only.
- Frontend Apache sends a restrictive Content Security Policy and browser
  hardening headers.
- Image bases are pinned by digest and application revisions are recorded.

Do not add privileged mode, host networking, host PID namespaces, wildcard CSP
script sources, `unsafe-eval`, or the Docker socket without a documented threat
review and a narrower alternative analysis.

## Tests and quality gates

Run the fast static validation before every change:

```bash
./scripts/validate.sh
```

It checks:

- Bash syntax;
- merged demo Compose validity;
- pinned Dockerfile base-image digests;
- absence of `latest`, build-time Git clones, disabled curl TLS verification,
  and embedded database passwords;
- required services and `no-new-privileges` settings;
- required Content Security Policy and security headers.

When build or runtime behavior changes, complete the full verification loop:

```bash
./scripts/build-local.sh --no-cache
./start-idelium.sh --demo
```

CI performs equivalent validation, rebuilds the images without cache, starts the
complete demo stack, waits for health, and exercises the public HTTPS endpoint.

## Repository layout

```text
.
├── docker-compose.yml       Shared services, health checks, volumes, and secrets
├── compose.demo.yml         Explicit demo seeds and development TLS
├── compose.production.yml   Trusted production certificate mount
├── compose.release.yml      Immutable external release images
├── start-idelium.sh         Mode-aware startup and smoke test
├── ideliumapi/              API Dockerfile, Apache, supervisor, and entrypoints
├── idelium-fe/              Web Dockerfile, Apache TLS proxy, and entrypoint
├── idelium-cli/             Optional CLI runner Dockerfile and entrypoint
├── ideliumdb/               MariaDB Dockerfile and initialization SQL
├── scripts/                 Validation, build, secret, and smoke-test tools
└── docs/                    Operational procedures
```

## Routine operations

### View running services

```bash
docker compose -f docker-compose.yml -f compose.production.yml ps
```

### Recreate after configuration or secret changes

Use the same Compose overlays as the running deployment and recreate only after
the replacement values are present. Keep previous secret versions available
until the new services pass health checks. Rotating Laravel `APP_KEY` invalidates
sessions and can affect encrypted data; follow an application key-rotation plan.

### Backup and rollback

Use an authenticated database backup tool appropriate to your environment and
store backups encrypted outside the Compose host. A release rollback restores
the previous set of three immutable image references. If a schema change is not
backward compatible, restore the matching database backup according to that
release's migration note.

Detailed procedures are in [Stack operations](docs/operations.md).

## Troubleshooting

### Startup times out

Inspect `ideliuminit` first because it gates API startup. Then inspect database,
API, and frontend health in order. Common causes are missing secret files,
incorrect permissions, database initialization failures, certificate mount
errors, and an occupied HTTPS port.

### Port 443 is already in use

Set another host port in `.env`, for example `HTTPS_PORT=8443`, and use
`https://localhost:8443`. Keep `APP_URL` and any client configuration aligned
with the externally visible origin.

### Production certificate is rejected

Verify that `TLS_CERT_DIR` is an existing directory containing readable
`server.crt` and `server.key`, the certificate covers the public hostname, the
chain is complete, and the files are replaced atomically. Do not disable TLS
verification to hide a production certificate error.

### API is unhealthy after initialization

Check API logs and migration status, then verify the application key and database
secret mounts. Do not paste the values or full environment into an issue.

### A local image does not contain the expected source

Use `./scripts/build-local.sh --no-cache` from clean sibling repositories. The
wrapper verifies source labels after the build. Inspect the recorded OCI revision
labels rather than relying only on a mutable local tag.

## Contributing

Read [`AGENTS.md`](AGENTS.md) before making changes. Documentation and comments
must be in clear English. Keep demo and production behavior separate, pin every
runtime and download, use secret files, add health checks for new services, and
run static validation plus a full no-cache stack test whenever build or runtime
behavior changes.

## Related projects

- [`idelium-api`](https://github.com/idelium/idelium-api) — Laravel backend.
- [`idelium-web`](https://github.com/idelium/idelium-web) — Vue administration UI.
- [`idelium-cli`](https://github.com/idelium/idelium-cli) — test execution agent.

Project information is available at [idelium.org](https://idelium.org/).
