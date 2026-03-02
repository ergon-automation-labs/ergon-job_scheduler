defmodule BotArmyJob.Application do
  @moduledoc """
  BotArmyJob application supervisor.

  Manages job scheduling bot services:
  - NATS message consumer
  - Job scheduler
  - Execution manager
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database connection
      BotArmyJob.Repo,

      # Job schedule storage
      {BotArmyJob.ScheduleStore, []},

      # NATS connection and consumer
      {BotArmyJob.NATS.Consumer, []}
    ]

    opts = [strategy: :one_for_one, name: BotArmyJob.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
