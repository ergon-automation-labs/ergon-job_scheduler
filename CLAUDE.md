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

---

## Agent Workflow Pattern

**Effective use of Claude Code agents when developing this bot.**

This follows the polyrepo agent strategy documented in `bot_army_infra/CLAUDE.md`.

### When to Use Haiku Agents

- Exploring handler implementations and understanding existing patterns
- Reading test files to understand expected behavior
- Diagnostics: checking test failures, understanding error logs
- Code search: finding specific handlers or NATS subjects
- Verification: running tests, checking message flow

**Why**: Fast iteration loop, perfect for understanding how other bots are structured.

### When to Use Sonnet Agents

- Implementing new handlers or business logic
- Designing complex scheduling algorithms and execution strategies
- Multi-handler integrations and message routing
- Refactoring handlers for new requirements
- Performance optimizations

**Why**: Deep reasoning ensures handlers are correct, scheduling logic is sound, and error cases are handled.

### Example: Add New Job Execution Strategy

```
User: "Add parallel job execution with dependency tracking"
  ↓
1. Haiku (Explore): Read existing execution_handler.ex, understand current execution model
  ↓
2. Sonnet (Plan): Design parallel execution strategy, identify state changes needed
   Plan dependency graph resolution, failure handling
  ↓
3. Sonnet (Implement): Update execution handler, add dependency tracking, add tests
  ↓
4. Haiku (Verify): Run test suite, check message flow and timing
```
