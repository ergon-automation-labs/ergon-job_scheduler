import Config

# Test against Kubernetes PostgreSQL (via NodePort)
# Uses same configuration as production, just with test database
config :bot_army_job, BotArmyJob.Repo,
  database: System.get_env("BOT_ARMY_JOB_DB_NAME", "bot_army_job_test"),
  hostname: System.get_env("BOT_ARMY_JOB_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_JOB_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_JOB_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_JOB_DB_PASSWORD", "postgres"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1
