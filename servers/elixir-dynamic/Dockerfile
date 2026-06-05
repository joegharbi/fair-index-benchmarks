# Fair Elixir dynamic server — mix release. No static file (body generated per request).
FROM elixir:1.19.5-otp-28 AS builder
ENV MIX_ENV=prod
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force
COPY mix.exs .
COPY lib ./lib
RUN mix deps.get --only prod && mix compile && mix release

FROM debian:trixie-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libncurses6 libssl3t64 ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/fair_index /app/rel
EXPOSE 80
CMD ["/app/rel/bin/fair_index", "start"]
