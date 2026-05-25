FROM ergon-automation-labs/ergon-builder:1.0.0 as builder

WORKDIR /app
RUN apk add --no-cache build-base git elixir
COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force && mix deps.get --only prod

COPY . .
RUN mix compile --prod && mix release

# Runtime
FROM ergon-automation-labs/ergon-builder:base

COPY --from=builder /app/_build/prod/rel/job_scheduler /app/bin/

ENV MIX_ENV=prod
ENV NATS_SERVERS=nats://nats:4222
ENV DATABASE_URL=postgres://postgres:postgres@postgres:5432/bot_army_prod

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8888/health || exit 1

CMD ["job_scheduler", "start"]
