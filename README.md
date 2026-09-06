# carolina-codes-erlang

Read-only v1 polyglot API for Carolina Code Conference. **Erlang/OTP** with **Nova** (Cowboy underneath) and **epgsql**.

`carolina_handler:handle_get/3` is the shipped router. Nova controllers parse path bindings and `year` query, call that unit, and return `{json, Map}` / `{json, Status, Headers, Map}`. Tests call those functions with a fake catalog — they do not reimplement routing. Live SQL uses epgsql against PostgreSQL `v1_*` views.

```bash
make test        # local eunit
make dialyzer
make sast        # PEST static security scan of src/
make audit       # Hex/GitHub advisory scan of locked deps
make lint        # Elvis
make check       # all of the above
make hooks       # install local pre-commit hooks
```

Pre-commit runs the same five checks (`dialyzer`, `local tests`, `static security scanner`, `3rd-party dependency scanner`, `elvis`). Install once with `make hooks` (needs `pre-commit` on PATH). Emergency skip: `SKIP=dialyzer,local-tests,sast,audit,elvis git commit`.

```bash
DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/carolina_dev \
CAROLINA_URL=http://127.0.0.1:4000 \
POLYGLOT_REGISTER_TOKEN=dev \
PUBLIC_BASE_URL=http://127.0.0.1:4028 \
PORT=4028 \
./bin/server
```

`GET /` reports `language: "Erlang"` and `framework: "Nova"`. `GET /health` returns `{"status":"ok"}` without touching Postgres. Listen port is **4028** locally and **8080** on Fly. The listener binds IPv6 dual-stack (`::`) so Fly 6PN can reach the process.

Local OTP is 29 via mise (`$HOME/.local/share/mise/installs/erlang/latest`). `bin/server` puts that prefix on `PATH` when `erl` is not already available. `rebar3` is `$HOME/.local/bin/rebar3`.
