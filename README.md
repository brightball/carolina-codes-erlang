# carolina-codes-erlang

Read-only v1 polyglot API for Carolina Code Conference. **Erlang/OTP** with **Nova** (Cowboy underneath), **epgsql**, and **thoas**.

## Versions

The image and Gitea CI use `erlang:27-slim` (`Dockerfile`, `.gitea/workflows/ci.yml`). `rebar.config` sets `minimum_otp_vsn` to 26, which is lower than that image. Local development uses mise `erlang/latest` (OTP 29 on the maintainer machine). That local install can move without a commit. Do not treat the image major, `minimum_otp_vsn`, and the local OTP as one number.

| Component | Version | Where |
|---|---|---|
| nova | 0.16.1 | `rebar.config` deps |
| epgsql | 4.7.1 | `rebar.config` deps |
| thoas | 1.2.1 | `rebar.config` deps |
| rebar3 (image and CI) | 3.25.1 | `Dockerfile` |
| rebar3_audit | 0.2.8 | `project_plugins` |
| rebar3_lint | 6.0.0 | `project_plugins` |
| gitleaks | 8.30.1 | `mise.toml` |

Nova is the HTTP framework. epgsql reads PostgreSQL `v1_*` views. thoas encodes JSON. Cowboy is Nova's HTTP server and is not a direct dependency. `rebar3_audit` and `rebar3_lint` are build plugins, not runtime applications.

`carolina_handler:handle_get/3` is the shipped router. Nova controllers parse path bindings and `year` query, call that unit, and return `{json, Map}` / `{json, Status, Headers, Map}`. Tests call those functions with a fake catalog — they do not reimplement routing. Live SQL uses epgsql against PostgreSQL `v1_*` views.

```bash
make test        # local eunit (shipped handler/catalog/http/register)
make dialyzer    # local type check; not one of the five Gitea jobs
make sast        # PEST static security scan of src/
make audit       # Hex/GitHub advisory scan of locked deps
make secrets     # gitleaks detect on this git tree
make lint        # Elvis via rebar3 lint
make check       # dialyzer + the five checks above
make hooks       # install local pre-commit hooks
```

Pre-commit runs Dialyzer plus the five required checks (`local tests`, `static security scanner`, `3rd-party dependency scanner`, `gitleaks`, `elvis`). Install once with `make hooks` (needs `pre-commit` on PATH). Emergency skip: `SKIP=dialyzer,local-tests,sast,audit,gitleaks,elvis git commit`.

Gitea Actions (`.gitea/workflows/ci.yml`) prepares the environment once, then runs the same five checks as separate jobs that `needs:` only that prepare stage: `test`, `sast`, `audit`, `gitleaks`, `lint`. `make test` compiles with warnings as errors and runs xref (`undefined_function_calls`) before eunit. Dialyzer stays on `make dialyzer` / pre-commit and is not a Gitea job. The production image and the Gitea job image are both `erlang:27-slim`.

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4028 \
PORT=4028 \
./bin/server
```

`GET /` reports `language: "Erlang"` and `framework: "Nova"`. `GET /health` returns `{"status":"ok"}` without touching Postgres. Listen port is **4028** locally and **8080** on Fly (`PORT`). The listener binds IPv6 dual-stack (`::`, `ipv6_v6only` false) so Fly 6PN can reach the process.

`./bin/server` execs a prebuilt boot (`config/vm.args`: one scheduler, no busy-wait). It does not compile. Run `make compile` first when `_build/default/lib` is missing. The Fly image builds that boot in a builder stage and the final image has no rebar3. Idle machines suspend (`auto_stop_machines = "suspend"`, 256MB shared-1cpu, `min_machines_running = 0`). A failed catalog query drops the cached epgsql connection and retries once on a new socket.

Local OTP is 29 via mise (`$HOME/.local/share/mise/installs/erlang/latest`). `bin/server` puts that prefix on `PATH` when `erl` is not already available. `rebar3` is `$HOME/.local/bin/rebar3`. `gitleaks` is mise `gitleaks@8.30.1`. Production and Gitea CI build with OTP 27.
