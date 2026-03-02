defmodule BotArmyJob.Repo do
  @moduledoc """
  Ecto Repository for the Job bot.

  Provides database access for job schedules with PostgreSQL backend.
  """

  use Ecto.Repo,
    otp_app: :bot_army_job,
    adapter: Ecto.Adapters.Postgres
end
