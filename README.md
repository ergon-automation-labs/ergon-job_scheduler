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
