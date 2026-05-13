# BotArmyJobScheduler

Job scheduling and management bot implementation for the Bot Army ecosystem.

Manages job scheduling, execution, and status tracking.

## Building

```bash
mix deps.get
mix test
```

## Running

```bash
iex -S mix
```

## Architecture

- **NATS Consumer** - Listens for job-related messages
- **Job Scheduler** - Manages job scheduling and timing
- **Execution Manager** - Handles job execution and status

## Built-in Schema Sync Job

`bot_army_job_scheduler` now seeds a default recurring schedule for schema drift checks:

- **Title:** `Schema Sync Drift Check`
- **Command:** `ops.schema_sync.run`
- **Default cron:** `*/30 * * * *`
- **Execution:** runs `make schema-sync-job PUBLISH=1 SUBJECT=synapse.context.schema_sync.report`

Environment overrides:

- `JOB_SCHEDULER_ENABLE_SCHEMA_SYNC` (default `true`) - set to `false` to disable seeding.
- `JOB_SCHEDULER_SCHEMA_SYNC_CRON` (default `*/30 * * * *`) - custom cadence.
- `JOB_SCHEDULER_SCHEMA_SYNC_TIMEOUT` (default `900`) - timeout in seconds for make job.
- `JOB_SCHEDULER_SCHEMA_SYNC_SUBJECT` (default `synapse.context.schema_sync.report`) - publish subject.
- `ELIXIR_BOTS_DIR` (default `/Users/abby/code/elixir_bots`) - repo root used when invoking `make`.

## Built-in PARA Daily Changed Job

`bot_army_job_scheduler` also seeds a daily PARA note writer:

- **Title:** `PARA Daily What Changed`
- **Command:** `ops.para_daily_changed.run`
- **Default cron:** `0 23 * * *` (UTC)
- **Execution:** runs `make bridge-para-daily-changed-smoke` in `ELIXIR_BOTS_DIR`, which requests `bridge.para.daily.changed.create`

Environment overrides:

- `JOB_SCHEDULER_ENABLE_PARA_DAILY_CHANGED` (default `true`) - set to `false` to disable seeding.
- `JOB_SCHEDULER_PARA_DAILY_CHANGED_CRON` (default `0 23 * * *`) - custom cadence.
- `JOB_SCHEDULER_PARA_DAILY_CHANGED_TIMEOUT` (default `300`) - timeout in seconds for the make job.
- `JOB_SCHEDULER_PARA_PROJECT_REF` (default `fractional_contractor_readiness`) - PARA project slug used in payload.

## Built-in Daily Learning Podcast Job

`bot_army_job_scheduler` seeds a recurring schedule for the learning podcast lane:

- **Title:** `Daily Learning Podcast`
- **Command:** `ops.daily_learning_podcast.run`
- **Default cron:** `0 12 * * *` (UTC; ~06:00 America/Denver during MDT)
- **Default status:** `paused` (resume after dry-run debugging)
- **Execution:** runs `make learning-podcast-job` in `ELIXIR_BOTS_DIR`

Environment overrides:

- `JOB_SCHEDULER_ENABLE_DAILY_LEARNING_PODCAST` (default `true`) - set to `false` to disable seeding.
- `JOB_SCHEDULER_DAILY_LEARNING_PODCAST_CRON` (default `0 12 * * *`) - custom cadence.
- `JOB_SCHEDULER_DAILY_LEARNING_PODCAST_TIMEOUT` (default `900`) - timeout in seconds for the make job.
- `JOB_SCHEDULER_DAILY_LEARNING_PODCAST_STATUS` (default `paused`) - initial schedule status.
- `LEARNING_PODCAST_DRY_RUN` (default `false`) - when `true`, scheduler runs `DRY_RUN=1`.
- `LEARNING_PODCAST_NO_INVOKE` (default `false`) - when `true`, scheduler runs `INVOKE=0`.

## Built-in Synapse scorecard signals + PARA

When `JOB_SCHEDULER_ENABLE_SYNAPSE_SCORECARD_SIGNALS` is `true`/`1`/`yes`, the bot seeds a daily schedule:

- **Title:** `Synapse scorecard signals + PARA`
- **Command:** `ops.synapse_scorecard_signals.run`
- **Default cron:** `30 13 * * *` (UTC)
- **Execution:** runs `make synapse-scorecard-signals-with-para` in `ELIXIR_BOTS_DIR` — LLM + agentic Synapse NATS publishes, then `para.fs.write` copies of the generated markdown into PARA (`inbox/bots/` by default).

This is **separate** from `ops.schema_sync.run` (which should keep its own cadence, e.g. every 30 minutes) so schema drift checks are not duplicated daily.

Environment overrides:

- `JOB_SCHEDULER_ENABLE_SYNAPSE_SCORECARD_SIGNALS` (default `false`) — must be enabled to seed.
- `JOB_SCHEDULER_SYNAPSE_SCORECARD_SIGNALS_CRON` (default `30 13 * * *`).
- `JOB_SCHEDULER_SYNAPSE_SCORECARD_SIGNALS_TIMEOUT` (default `3600`) — seconds for the combined `make` run.
- `PARA_FS_WRITE_TOKEN` — if the `para.fs.write` responder requires auth, set the same token in `job_scheduler.env`.
- `PORT` / `NATS_PORT` — broker port for scorecard publish + `para.fs.write` (default `4222`).

## Message Schemas

Schemas are defined in `bot_army_schemas_job` and deployed to `/etc/bot_army/schemas/job/`

## Dependencies

- `bot_army_core` - Core NATS decoder and envelope handling
- `nats` - NATS client library
- `jason` - JSON encoding/decoding
- `logger_json` - JSON logging

## Development

```bash
make setup    # Install dependencies
make test     # Run tests
make check    # Run all checks
```

## Related Repositories

- `bot_army_schemas_job` - Job message schemas
- `bot_army_core` - Core library
- `bot_army_infra` - Deployment infrastructure
