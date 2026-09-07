FROM erlang:27-slim
USER root
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl make \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /usr/local/bin/rebar3 https://github.com/erlang/rebar3/releases/download/3.25.1/rebar3 \
 && chmod +x /usr/local/bin/rebar3
