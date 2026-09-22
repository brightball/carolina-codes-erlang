# OTP 27 matches Gitea CI (.gitea/workflows/ci.yml). The builder compiles;
# the runtime image only has the prebuilt beams and the VM.
FROM erlang:27-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSL -o /usr/local/bin/rebar3 https://github.com/erlang/rebar3/releases/download/3.25.1/rebar3 \
 && chmod +x /usr/local/bin/rebar3
COPY rebar.config rebar.lock ./
COPY src ./src
COPY config ./config
COPY priv ./priv
# prod/lib symlinks dependencies back at the builder. Copy real ebin/priv
# so the runtime image can load them.
RUN rebar3 as prod compile \
 && mkdir -p /out/lib \
 && for app in /src/_build/prod/lib/*; do \
      name="$(basename "$app")"; \
      if [ "$name" = ".rebar3" ]; then continue; fi; \
      target="$(readlink -f "$app")"; \
      mkdir -p "/out/lib/$name"; \
      if [ -d "$target/ebin" ]; then cp -a "$target/ebin" "/out/lib/$name/ebin"; fi; \
      if [ -d "$target/priv" ]; then cp -a "$target/priv" "/out/lib/$name/priv"; fi; \
    done \
 && test -f /out/lib/carolina/ebin/carolina.app \
 && test -f /out/lib/epgsql/ebin/epgsql.app \
 && test -f /out/lib/nova/ebin/nova.app

FROM erlang:27-slim
# erlang:27-slim ships a rebar3 binary. The running image must not.
RUN rm -f /usr/local/bin/rebar3
WORKDIR /app
COPY --from=build /out/lib ./lib
COPY config ./config
COPY bin/server ./bin/server
RUN chmod +x /app/bin/server
ENV PORT=8080
EXPOSE 8080
CMD ["/app/bin/server"]
