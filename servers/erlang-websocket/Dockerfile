# Fair Erlang WebSocket echo server — rebar3 release.
FROM erlang:28.4.2 AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL -o /usr/local/bin/rebar3 https://s3.amazonaws.com/rebar3/rebar3 \
    && chmod +x /usr/local/bin/rebar3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
COPY rebar.config .
COPY src ./src
RUN rebar3 as prod release

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libncurses6 libssl3t64 ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/fair_index /app/rel
EXPOSE 80
CMD ["/app/rel/bin/fair_index", "foreground"]
