# carolina-codes-erlang

Finished read-only v1 HTTP API for the Carolina Code Conference polyglot
fleet. The OTP application is `carolina`. HTTP is **Nova** (Nordix) on Cowboy,
not a hand-rolled Cowboy application. JSON is **thoas**. SQL is **epgsql**
against PostgreSQL `v1_*` views. Payloads are ordinary JSON, not Ash JSON:API
(`application/vnd.api+json`).

This tree is the finished service. It is not the language starter. This
repository does not contain `openapi.yaml`, `db/*.sql`, `docker-compose.yml`,
`tests/test_catalog.py`, or `images/`. Do not add those paths here.

## Where facts live

Read this file for how to work, [DECISIONS.md](DECISIONS.md) for why, and
[MEMORY.md](MEMORY.md) for current commands, ports, and gotchas.

- How-to-work rules go in `AGENTS.md`.
- Why goes in `DECISIONS.md`. Append a new entry, or mark an old entry
  superseded. Do not silently rewrite history. Accepted entries are binding.
  A change that conflicts with one updates that record in the same commit.
- Operational facts that are not the why go in `MEMORY.md` and are updated
  in place when they change.
- Keep secrets out of all three: no API keys, tokens, production passwords,
  or secret-file contents. The published local examples
  (`POLYGLOT_REGISTER_TOKEN=dev`,
  `postgres://postgres:postgres@127.0.0.1:5432/carolina_dev`) may stay.

Package and OTP versions are stated in [README.md](README.md). They are read
from `rebar.config` and the `erlang:` image in `Dockerfile`.

## Workspace

Treat **this repo** as the workspace root. Do not assume `../elixir` or any
other sibling checkout exists. The Phoenix CMS is a different git remote
(`github.com/brightball/carolina-codes`). Do not fold this tree into that
remote. Do not query Ash tables.

The HTTP contract is the CMS `priv/api/openapi.yaml` and `priv/api/AGENTS.md`.
You do not need a CMS checkout to run the unit tests. Registration is
best-effort: if `CAROLINA_URL` is unset or the CMS is down, skip the register
call and still serve HTTP.

## Purpose

The Phoenix app keeps **at most one** language API warm and reads the catalog
from it. This process must:

1. Query PostgreSQL **v1 views** only. Never Ash resource tables or other
   base tables (`speakers`, `organizations`, `talks`, and the rest).
2. Expose the v1 REST routes below as ordinary JSON.
3. **Register once on boot**. No heartbeat. If the site is not running, log
   and continue.

Views used by `carolina_handler`: `v1_years`, `v1_speakers`, `v1_talks`,
`v1_sponsors`, `v1_year_sponsors`, `v1_sponsorships`. They live in the CMS
database. Year-scoped speaker rows include `languages` and `topics`.
Year-scoped sponsor rows include `tier` and `blurb`.

## Environment

| Variable | Example | Role |
|---|---|---|
| `DATABASE_URL` | `postgres://postgres:postgres@127.0.0.1:5432/carolina_dev` | SQL views |
| `CAROLINA_URL` | `http://127.0.0.1:4000` | Elixir site (optional; register no-ops if down) |
| `POLYGLOT_REGISTER_TOKEN` | `dev` | Bearer token for register |
| `PUBLIC_BASE_URL` | `http://127.0.0.1:4028` | URL the CMS will call |
| `PORT` | `4028` locally, `8080` in the image | Listen port |

## HTTP

`carolina:start/2` calls `carolina_http:listen/0`, which configures Nova and
starts it. Routes are `carolina_router:routes/1`. Controllers parse bindings
and the `year` query, then call `carolina_handler:handle_get/3`.

- `GET /health` — `{ "status": "ok" }`. Does not touch Postgres.
- `GET /` — identity (`language` Erlang, `framework` Nova, versions, endpoints)
- `GET /v1/years`
- `GET /v1/speakers` and `GET /v1/speakers?year=`
- `GET /v1/speakers/{slug}` and `GET /v1/speakers/{year}/{slug}`
- `GET /v1/sponsors` and `GET /v1/sponsors?year=`
- `GET /v1/sponsors/{slug}` and `GET /v1/sponsors/{year}/{slug}`

List payloads are `{ "data": [ ... ] }`. An unknown slug is HTTP 404.
`photo_path` and `logo_path` are web paths. This process returns the path
and does not serve image bytes.

The listener is dual-stack IPv6 (`::`, `ipv6_v6only` false) from
`carolina_http:cowboy_configuration/0` and `config/sys.config`.

## Register on boot (once)

`POST {CAROLINA_URL}/internal/api-endpoints/register`

```
Authorization: Bearer {POLYGLOT_REGISTER_TOKEN}
Content-Type: application/json
```

Body fields, from `carolina_identity`: `language`, `language_version`,
`api_version`, `framework`, `created_year`, `base_url` (`PUBLIC_BASE_URL`),
`schema_version` (1), `endpoints` (list of method and path).

Do not heartbeat. The CMS keep-alives the warm API.

If `CAROLINA_URL` or `POLYGLOT_REGISTER_TOKEN` is empty, or the POST fails
(connection refused, 4xx/5xx), log and keep serving.

## OTP and quality checks

The production image and Gitea CI use the `erlang:` tag in `Dockerfile`
(OTP 27, `erlang:27-slim`). `rebar.config` `minimum_otp_vsn` is 26. Local
OTP is mise `erlang/latest` and can be newer than the image (OTP 29 on the
maintainer machine). README states all three. Do not collapse them into one
number.

Five checks, as `make` targets and as separate jobs in
`.gitea/workflows/ci.yml`. Each check job `needs:` only `prepare`.

| Check | Make | Gitea job |
|---|---|---|
| unit tests | `make test` | `test` |
| static analysis (PEST over `src/`) | `make sast` | `sast` |
| locked-dep advisory scan | `make audit` | `audit` |
| gitleaks | `make secrets` | `gitleaks` |
| Elvis (`rebar3 lint`) | `make lint` | `lint` |

Dialyzer is `make dialyzer` and the pre-commit hook
(`.githooks/pre-commit`, `.pre-commit-config.yaml` id `dialyzer`). It is not
a Gitea job. `make check` is Dialyzer plus the five checks. `make test`
compiles with warnings as errors and runs xref before eunit.

Handler tests inject a fake catalog into `handle_get/3`. They do not need
Postgres. Call that function. Do not reimplement routing inside a test.

## Layout

| Path | Role |
|---|---|
| `src/` | OTP application `carolina` |
| `src/carolina_router.erl` | Nova route table |
| `src/carolina_handler.erl` | GET routing and view SQL |
| `src/carolina_catalog.erl` | epgsql |
| `src/carolina_register.erl` | one-shot register |
| `src/controllers/` | Nova controllers |
| `config/sys.config` | Nova listener config |
| `Dockerfile` | multi-stage `erlang:27-slim` image |
| `Makefile` | local quality entry points |
| `.gitea/workflows/ci.yml` | the five checks |
| `test/` | eunit |
| `DECISIONS.md` | why |
| `MEMORY.md` | operational facts |

## Checklist

- [ ] OpenAPI paths return ordinary JSON (404 on an unknown slug)
- [ ] `?year=` speaker rows include `languages` and `topics`; sponsor rows include `tier`
- [ ] Register runs once at process start and no-ops if the CMS is down
- [ ] No writes; no Ash table names; no Ash JSON:API
- [ ] `GET /health` does not query the database
- [ ] README versions match `rebar.config` and the `Dockerfile` image
