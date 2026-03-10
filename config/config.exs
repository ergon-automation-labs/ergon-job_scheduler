import Config

# Ecto repositories for migrations
config :bot_army_job, ecto_repos: [BotArmyJob.Repo]

# Database configuration from Salt/Helm environment variables
config :bot_army_job, BotArmyJob.Repo,
  database: System.get_env("BOT_ARMY_JOB_DB_NAME", "bot_army_job"),
  hostname: System.get_env("BOT_ARMY_JOB_DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("BOT_ARMY_JOB_DB_PORT", "5432")),
  username: System.get_env("BOT_ARMY_JOB_DB_USER", "postgres"),
  password: System.get_env("BOT_ARMY_JOB_DB_PASSWORD", "postgres"),
  pool_size: 10

# Import environment-specific config
if File.exists?("config/#{Mix.env()}.exs") do
  import_config "#{Mix.env()}.exs"
end
