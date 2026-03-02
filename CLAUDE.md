# CLAUDE.md

Guidance for Claude Code when working with `bot_army_job`.

---

## Purpose

**bot_army_job** is the job scheduling and management bot implementation.

Handles:
- Job scheduling and timing management
- Execution orchestration
- Status tracking and reporting
- Error handling and retries

---

## File Organization

```
.
├── lib/
│   ├── bot_army_job.ex                  # Main module
│   └── bot_army_job/
│       ├── application.ex                # Application supervisor
│       ├── nats/
│       │   └── consumer.ex               # NATS message consumer
│       └── handlers/
│           ├── schedule_handler.ex
│           ├── execution_handler.ex
│           └── status_handler.ex
├── test/
│   ├── test_helper.exs
│   └── bot_army_job/
│       ├── nats/
│       │   └── consumer_test.exs
│       └── handlers/
│           └── schedule_handler_test.exs
├── mix.exs
├── CLAUDE.md
└── README.md
```

---

## Core Dependencies

- **bot_army_core** - NATS envelope decoding, schema validation
- **nats** - NATS client for message publishing/subscribing
- **jason** - JSON encoding/decoding
- **logger_json** - Structured JSON logging

The bot depends on schemas deployed by `bot_army_schemas_job` at `/etc/bot_army/schemas/job/`

---

## Development Workflow

### Setup

```bash
mix deps.get
mix test
```

### Key Modules to Implement

1. **BotArmyJob.NATS.Consumer** - Subscribe to NATS subjects
2. **BotArmyJob.Handlers.ScheduleHandler** - Handle job scheduling
3. **BotArmyJob.Handlers.ExecutionHandler** - Manage job execution
4. **BotArmyJob.Handlers.StatusHandler** - Track job status

### Message Subjects

The bot listens to and publishes:
- `job.schedule.*` - Job scheduling operations
- `job.execution.*` - Job execution operations
- `job.status.*` - Job status updates

All messages follow the core envelope structure from `bot_army_core`.

---

## Testing

```bash
mix test                    # Run all tests
mix test --cover            # With coverage
mix credo                   # Linting
mix dialyzer                # Static analysis
```

---

## Deployment

This bot is deployed via Salt from `bot_army_infra`:

```bash
cd ../bot_army_infra
make deploy-bot BOT=job
```

Deployment happens after:
1. Core schemas deployed
2. bot_army_core library deployed

---

## Related Repositories

- `bot_army_schemas_job` - Job message schemas
- `bot_army_core` - Core library and NATS decoder
- `bot_army_infra` - Deployment infrastructure
