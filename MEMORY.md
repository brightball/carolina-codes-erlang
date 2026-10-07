# Memory

Current operational facts for carolina-codes-erlang (Erlang/OTP + Nova).
This file is not the why ([DECISIONS.md](DECISIONS.md)) and not the working
rules ([AGENTS.md](AGENTS.md)). Update an entry in place when the fact
changes. Do not append a log of old values.

No secrets. Do not paste API keys, tokens, production passwords, or anything
from `~/.config`. The local `DATABASE_URL` and `POLYGLOT_REGISTER_TOKEN=dev`
examples below are the published development defaults already in the source.

## Commands

```bash
make compile     # rebar3 compile; required before ./bin/server
make test        # xref, then eunit (warnings as errors)
make dialyzer    # local only; not a Gitea job
make sast        # tools/pest/pest.erl -e -r src
make audit       # env -u GITHUB_TOKEN rebar3 audit
make secrets     # gitleaks detect, plus a staged scan when the index is dirty
make lint        # rebar3 lint (Elvis)
make check       # dialyzer, then the five checks
make hooks       # pre-commit install and core.hooksPath .githooks
make run         # compile, then ./bin/server
```

Pre-commit (`.githooks/pre-commit`) runs `pre-commit` when it is on `PATH`,
otherwise the same Makefile targets. Hook ids: `dialyzer`, `local-tests`,
`sast`, `audit`, `gitleaks`, `elvis`. Emergency skip names match those ids.

`make test` is the suite. Tests live in `test/*_tests.erl` and call the
shipped modules.

## Versions and ports

- Image and Gitea CI: `erlang:27-slim` in `Dockerfile` and
  `.gitea/workflows/ci.yml`. rebar3 in that image is 3.25.1.
- `rebar.config` `minimum_otp_vsn` is 26. That is a floor, not the image.
- Local OTP is mise `erlang/latest` (`~/.local/share/mise/installs/erlang/latest`).
  The maintainer machine is OTP 29. `bin/server` prepends that prefix when
  `erl` is not already on `PATH`. `rebar3` is `~/.local/bin/rebar3`.
- Direct deps in `rebar.config`: nova 0.16.1, epgsql 4.7.1, thoas 1.2.1.
- `project_plugins`: rebar3_audit 0.2.8, rebar3_lint 6.0.0. They are not in
  the release.
- gitleaks is mise 8.30.1 (`mise.toml`).
- Application env default port is 4028 (`carolina.app.src`). `PORT` overrides
  it in `carolina:port/0`. The image sets `PORT=8080`.
- `config/sys.config` also says port 4028. `carolina_http:configure_nova/0`
  replaces Nova's `cowboy_configuration` at listen time, so a running process
  follows `PORT`, not a stale literal in that file. Keep both maps dual-stack.
- `./bin/server` execs a prebuilt boot (`config/vm.args`). It does not compile.
  It looks for `lib/carolina/ebin`, then `_build/prod/lib`, then
  `_build/default/lib`. Missing beams exit with "prebuilt boot missing".
- `config/vm.args`: one scheduler (`+S 1:1`), busy-wait off, `+A 1`,
  `-noshell -noinput`. `bin/server` sets `ERL_CRASH_DUMP_SECONDS=0`.

## HTTP and catalog gotchas

- OTP application name is `carolina`. Nova `bootstrap_application` is
  `carolina`. There is no `carolina_codes` application.
- The supervisor (`carolina_sup`) has no children. The listener and the
  one-shot register start from `carolina:start/2`.
- `routing_tree` commits to the first matching binding and does not try the
  next sibling. Year routes are declared as `/:slug/:name` before `/:slug`.
  The public path is still `/v1/speakers/{year}/{slug}` (and the same for
  sponsors). In the controller, `:slug` is the year and `:name` is the slug.
- `GET /health` is the handler's JSON. It does not query Postgres.
- Unknown slug: `{json, 404, #{}, #{error => <<"not_found">>}}`.
- List bodies are `#{data => [...]}` after `carolina_json:row/1`.
- Year query values arrive as binaries. `carolina_catalog` coerces an
  all-digit binary to an integer before `epgsql:equery`. epgsql will not
  encode `<<"2026">>` as int8.
- The epgsql connection is cached in `persistent_term` and unlinked from the
  caller. A dead socket must not kill the request. On a connection failure
  the cache is dropped and the query runs once more. Do not call
  `epgsql:close/1` on a dead fd. It can block. The code kills the socket
  process instead. Query timeout is 5000 ms.
- `DATABASE_URL` unset or empty selects the local development URL
  `postgres://postgres:postgres@127.0.0.1:5432/carolina_dev`.
- Outbound TCP to a host ending in `.flycast`, `.internal`, or `.fly.io`
  adds `tcp_opts => [inet6]`. Other hosts stay on the default family.
- Register uses `httpc` profile `carolina_httpc`. `ipfamily` is `inet6` only
  when the URL contains `.internal:`. Do not set that option on the default
  `httpc` profile. Timeouts are 8000 ms. Failure is logged to stderr and
  ignored.
- `GET /` reports `language_version` from `erlang:system_info(otp_release)`
  of the running VM, so a local OTP 29 process and the OTP 27 image report
  different strings. That is expected.

## CI and secrets

- Gitea jobs run on `erlang:27-slim`. `prepare` installs git, make, curl,
  rebar3 3.25.1, and gitleaks, then uploads an artifact. Check jobs restore
  it with `tools/ci-env.sh`. They do not `apt-get`, clone, or download tools
  again. Restore is inlined. Gitea 1.24.7 rejects YAML anchors when it splits
  jobs. Do not add anchors, `git init`, `init.defaultBranch`, or
  `actions/checkout`.
- `make audit` and the audit job unset `GITHUB_TOKEN`. Gitea injects that
  name as a Gitea token. hex_core would send it to GitHub's advisory API and
  get 401. Audit needs a network path to Hex. If the network is down, the
  check is unverifiable. Do not fake a green report.
- `make secrets` runs `gitleaks detect --source . --verbose --redact`, then
  `gitleaks git --pre-commit --staged` when the index is dirty. Do not use
  `gitleaks detect --no-git`. That walk enters `_build` and false-positives
  on vendored deps.
- Elvis (`elvis.config`) lints `src/*.erl`, `src/controllers/*.erl`, and
  `rebar.config`. It does not lint `test/`. Dialyzer's PLT is local
  (`plt_location` local) and includes the runtime deps plus `inets` and `ssl`.
- `erl_opts` includes `warnings_as_errors`. xref checks
  `undefined_function_calls` and `undefined_functions` before eunit.
