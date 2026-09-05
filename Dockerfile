FROM erlang:27-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
RUN curl -fsSL -o /usr/local/bin/rebar3 https://github.com/erlang/rebar3/releases/download/3.25.1/rebar3 \
 && chmod +x /usr/local/bin/rebar3
COPY rebar.config rebar.lock ./
COPY src ./src
COPY bin ./bin
RUN rebar3 compile && chmod +x bin/server
ENV PORT=8080
EXPOSE 8080
CMD ["/app/bin/server"]
