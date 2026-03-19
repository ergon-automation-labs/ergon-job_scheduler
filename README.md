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
