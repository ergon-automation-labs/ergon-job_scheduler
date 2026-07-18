defmodule BotArmyJobScheduler.Release do
  @moduledoc """
  Release tasks for the Job Scheduler bot.

  Migrations are run via the shared BotArmyLibraryRuntime.Ecto.MigrationRunner:

      /path/to/job_scheduler/bin/job_scheduler eval 'BotArmyJobScheduler.Release.migrate()'

  Called from Salt during bot deployment, before the bot starts.
  """

  @app :bot_army_job_scheduler

  def migrate do
    BotArmyLibraryRuntime.Ecto.MigrationRunner.run(
      repo_module: BotArmyJobScheduler.Repo,
      app_module: @app
    )
  end
end
