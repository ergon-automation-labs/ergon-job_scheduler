# Getting Started with bot_army_job

This guide walks you through setting up the Job Bot for local development.

## Prerequisites

- **Elixir 1.14+** - Install via [elixir-lang.org](https://elixir-lang.org)
- **Erlang/OTP 25+** - Installed with Elixir
- **PostgreSQL** - For local database (optional for development)
- **Git** - For version control
- **GitHub CLI** (`gh`) - For releasing to GitHub

## Quick Start

### 1. Install Dependencies

```bash
make setup
```

This will:
- Initialize git if needed
- Run `mix deps.get`
- Install git hooks for pre-push validation

### 2. Verify Setup

```bash
mix compile
mix test
```

## Development Workflow

### Code Changes

```bash
# Make your changes
edit lib/bot_army_job.ex

# Format code
make format

# Run linter
make credo

# Run tests
make test
```

### Pushing to GitHub

```bash
git add .
git commit -m "Description of changes"
git push
```

When you push to `main`:
1. Pre-push hook runs `mix compile` and `mix credo`
2. Builds OTP release with `mix release`
3. Creates tarball
4. Publishes release to GitHub
5. Push completes

Jenkins automatically detects the new release and deploys it.

### Manual Release (if needed)

```bash
make release          # Build release locally
make publish-release  # Package and publish to GitHub
```

## Key Commands

```bash
make help             # Show all available commands
make setup            # Install dependencies and git hooks
make test             # Run tests
make credo            # Run linter
make check            # Run all checks (test, credo, dialyzer)
make format           # Format Elixir code
make clean            # Remove build artifacts
```

## Release Configuration

The OTP release is configured in `mix.exs`:

```elixir
releases: [
  job_bot: [
    applications: [bot_army_job: :permanent]
  ]
]
```

This creates a release named `job_bot` that is deployed to `/opt/ergon/releases/job_bot/` on the server.

## Configuration

### Development Environment

Create a `.env` file in the project root for local development:

```bash
DATABASE_HOST=localhost
DATABASE_PORT=5432
DATABASE_USER=postgres
DATABASE_PASSWORD=postgres
DATABASE_NAME=bot_army_job_dev
```

### Runtime Configuration

In production, configuration comes from Salt pillar via environment variables. See `pillar/common.sls` in `bot_army_infra` for details.

## Dependencies

Key dependencies:
- `bot_army_core` - Core library and NATS decoder
- `bot_army_runtime` - Persistence and messaging foundation
- `nats` - NATS client for message publishing/subscribing
- `jason` - JSON encoding/decoding
- `logger_json` - Structured JSON logging

Development dependencies:
- `credo` - Code linting
- `dialyxir` - Static type checking
- `excoveralls` - Code coverage

## Deployment

Deployment is automated via Jenkins. After you push to `main`:

1. Jenkins detects the new release on GitHub
2. Downloads the pre-built tarball
3. Extracts and deploys to `/opt/ergon/releases/job_bot/`
4. Restarts the service

No manual deployment steps needed.

## Troubleshooting

### Build Fails: "Release directory not found"

Make sure the release name in `mix.exs` is correct:
```elixir
releases: [
  job_bot: [
    applications: [bot_army_job: :permanent]
  ]
]
```

### Database Connection Issues

Check `.env` file and `config/dev.exs`. Environment variables must match your local setup.

### Pre-push Hook Fails

The hook validates compilation and builds the release. If it fails:

1. Run `mix deps.get` to ensure dependencies are up to date
2. Run `mix compile` to check for compilation errors
3. Run `mix credo --strict` to check for linting issues
4. Fix errors and try pushing again

### GitHub Release Already Exists

The pre-push hook will warn if a release already exists but will continue with the push. You can safely retry or manually create a new release with a different version.

## Related Documentation

- `../../README.md` - Project overview
- `bot_army_repo_structure_1.md` in `bot_army_schemas` - Full polyrepo context
- `bot_army_infra` - Infrastructure and deployment configuration

## Questions?

Check the Makefile for all available commands or review the `CLAUDE.md` file for development guidelines.
