# Decisions

Architecture decision records for this Erlang/OTP + Nova service.
One choice per entry. Status is `accepted`, `superseded`, or `deprecated`.

Append a new entry when a durable choice is made. When a choice changes,
add the new entry and set the old entry's status to `superseded by ADR-NNNN`.
Do not silently rewrite history. Git history is the changelog of an entry's
wording. Do not keep an amendment log inside the entry.

Accepted entries are binding. A task that conflicts with one stops and
updates the record (append, or supersede) in the same change.

How to work in the tree is [AGENTS.md](AGENTS.md). Current commands and
gotchas are [MEMORY.md](MEMORY.md). Secrets do not belong in any of them:
no API keys, tokens, production passwords, or secret-file contents.

These entries were written on 2026-10-07 from the code as it stood. They
record choices already in the tree, not a proposal.

## ADR-0001: Nova is the HTTP layer

### Status

Accepted

### Context

The service must serve a small, fixed set of GET routes. A hand-rolled
Cowboy dispatch would do that, and Cowboy is still the HTTP server underneath.

### Decision

Use Nova as the HTTP application. `carolina_router` implements `nova_router`.
`carolina_http:listen/0` sets Nova's environment and starts the `nova`
application. Controllers adapt the request and call `carolina_handler`.

### Consequences

There is no second Cowboy dispatch in this repo. Sessions and Nova's HTML
error pages are off (`use_sessions` false, `render_error_pages` false).
Cowboy stays a transitive dependency. `rebar.config` overrides Cowboy's deps
only because its Hex metadata uses a boolean form older rebar3 cannot parse.
Listener options live in Nova's `cowboy_configuration`.

## ADR-0002: thoas encodes JSON

### Status

Accepted

### Context

Clients and the CMS expect ordinary JSON objects. Ash JSON:API
(`application/vnd.api+json`) is a different contract and is out of scope.

### Decision

Encode with thoas through `carolina_json`. thoas is a direct dependency.
jsx and jiffy are not.

### Consequences

Handlers return `{json, Map}` or `{json, Status, Headers, Map}`. Key shaping
(booleans, years, tag lists) happens before encode. Swapping the JSON
library means a new decision and a `rebar.config` change, not a quiet
substitute inside a controller.

## ADR-0003: epgsql reads only v1_* views

### Status

Accepted

### Context

Catalog rows are owned by the Phoenix CMS. The public contract is the SQL
views, not the Ash tables under them. This repository does not ship the
schema.

### Decision

`carolina_catalog` queries with epgsql. The statements in `carolina_handler`
read only `v1_years`, `v1_speakers`, `v1_talks`, `v1_sponsors`,
`v1_year_sponsors`, and `v1_sponsorships`. There are no writes.

### Consequences

Schema and seed changes belong in the CMS. A dead cached socket is dropped
and the query is retried once. Year bind parameters are integers because
those columns are int8. Unit tests do not open a database. See ADR-0007.

## ADR-0004: OTP 27 for the image and CI

### Status

Accepted

### Context

Developers run mise `erlang/latest`, which moves. The image that Fly and
Gitea build must stay repeatable. rebar3 also has a minimum OTP it will
accept, and that floor is not the image tag.

### Decision

`Dockerfile` and `.gitea/workflows/ci.yml` use `erlang:27-slim`.
`rebar.config` sets `minimum_otp_vsn` to 26. Local development uses mise
`erlang/latest`. The image installs rebar3 3.25.1.

### Consequences

README states the image major, `minimum_otp_vsn`, and the local mise track
separately. Do not bump the image to match a developer machine. Do not
raise `minimum_otp_vsn` to the local major. An OTP change is a new entry
that supersedes this one.

## ADR-0005: Dual-stack listen

### Status

Accepted

### Context

The process must accept IPv4 and IPv6 on one port. Nova's default listen
is IPv4-only, which drops IPv6 clients, including Fly 6PN.

### Decision

`carolina_http:cowboy_configuration/0` and `config/sys.config` set
`ip` to `{0,0,0,0,0,0,0,0}` and `ipv6_v6only` to false. `carolina:port/0`
supplies the port (`PORT`, otherwise 4028).

### Consequences

One socket accepts both families. Outbound Postgres and the register POST
select IPv6 only for hosts that are AAAA-only. That selection is described
in MEMORY.md. Do not "simplify" the bind back to IPv4.

## ADR-0006: Register once, and no-op when the CMS is down

### Status

Accepted

### Context

The CMS keeps at most one language API warm and keep-alives that process.
A heartbeat from this service would fight that. The service is still useful
when no CMS is running.

### Decision

`carolina:start/2` spawns `carolina_register:once/0` a single time.
That function POSTs `{CAROLINA_URL}/internal/api-endpoints/register` with
`Authorization: Bearer {POLYGLOT_REGISTER_TOKEN}`. An empty URL, an empty
token, or any connection or HTTP failure logs and returns `ok`. There is
no timer and no retry loop.

### Consequences

Boot does not depend on the CMS. Do not add a heartbeat. The call uses its
own `httpc` profile (`carolina_httpc`) so `ipfamily` is not applied to the
default profile. Registration is not a supervised child. A crash there does
not stop the listener.

## ADR-0007: Unit tests call the handler with a fake catalog

### Status

Accepted

### Context

The view SQL needs the CMS database. Route shape, status codes, and JSON
shape do not.

### Decision

`carolina_handler:handle_get/3` takes the query function. Production
controllers pass `carolina_catalog:query/2`. Tests pass a fake. The same
pattern is used for catalog socket calls that must run without Postgres.

### Consequences

`make test` does not need `DATABASE_URL`. A test that reimplements routing,
or that hard-codes a response the handler did not produce, is the wrong
shape. Do not add a second test stack. Live SQL is an integration concern
and is not what eunit covers.

## ADR-0008: Five Gitea checks, Dialyzer local only

### Status

Accepted

### Context

The fleet requires five checks: unit tests, static analysis, a third-party
dependency scan, secret scanning, and a formatter or linter. Dialyzer is
worth running and is slow. It is not one of those five.

### Decision

`.gitea/workflows/ci.yml` runs `test`, `sast` (PEST over `src/`), `audit`
(`rebar3 audit`), `gitleaks`, and `lint` (Elvis) as separate jobs after
`prepare`. Each check job depends only on `prepare`. Dialyzer runs as
`make dialyzer` and as the pre-commit hook id `dialyzer`. Plugins
`rebar3_audit` and `rebar3_lint` are `project_plugins`, not runtime deps.

### Consequences

`make check` is Dialyzer plus the five. CI `audit` clears `GITHUB_TOKEN`
because a Gitea job token is rejected by GitHub's advisory API. Gitleaks
stays git-aware (`gitleaks detect` on the repo, plus a staged scan). Do not
point it at the working tree with `--no-git`. Do not add Dialyzer as a
sixth required Gitea job unless a later entry supersedes this one.
