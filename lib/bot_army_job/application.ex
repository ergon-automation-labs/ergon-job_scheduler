defmodule BotArmyJob.Application do
  @moduledoc """
  BotArmyJob application supervisor.

  Manages job scheduling bot services:
  - NATS message consumer
  - Job scheduler
  - Execution manager
  """

  use Application

  @env Mix.env()

  @impl true
  def start(_type, _args) do
    children = []
    |> maybe_add_repo()
    |> maybe_add_schedule_store()
    |> maybe_add_consumer()

    opts = [strategy: :one_for_one, name: BotArmyJob.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp maybe_add_repo(children) do
    if @env == :test, do: children, else: [BotArmyJob.Repo | children]
  end

  defp maybe_add_schedule_store(children) do
    if @env == :test, do: children, else: [{BotArmyJob.ScheduleStore, []} | children]
  end

  defp maybe_add_consumer(children) do
    if @env == :test, do: children, else: [{BotArmyJob.NATS.Consumer, []} | children]
  end
end
