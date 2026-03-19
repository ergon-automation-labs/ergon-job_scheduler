import Config

# Test configuration uses mocks instead of real database
config :bot_army_job, :schedule_store, BotArmyJobScheduler.ScheduleStoreMock

# Real database config (for integration tests only if needed)
config :bot_army_job, BotArmyJobScheduler.Repo,
  database: System.get_env("BOT_ARMY_JOB_TEST_DB_NAME", "ergon_job_test"),
  hostname: System.get_env("BOT_ARMY_JOB_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_JOB_DB_PORT", "30003")),
  username: System.get_env("BOT_ARMY_JOB_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_JOB_DB_PASSWORD", "postgres"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1
