# Fair Erlang index server — built as a rebar3 release (no dev tooling resident).
# Stage 1: build
FROM erlang:28.4.2 AS builder

# rebar3 is not in the base image; fetch the official escript.
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && curl -fsSL -o /usr/local/bin/rebar3 https://s3.amazonaws.com/rebar3/rebar3 \
    && chmod +x /usr/local/bin/rebar3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY rebar.config .
COPY src ./src
RUN rebar3 as prod release

# Stage 2: minimal runtime (release bundles ERTS)
FROM debian:trixie-slim
RUN apt-get update && apt-get install -y \
    libncurses6 \
    libssl3t64 \
    ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mkdir -p /var/www/html
COPY index.html /var/www/html/index.html
COPY --from=builder /app/_build/prod/rel/fair_index /app/rel

EXPOSE 80
CMD ["/app/rel/bin/fair_index", "foreground"]
