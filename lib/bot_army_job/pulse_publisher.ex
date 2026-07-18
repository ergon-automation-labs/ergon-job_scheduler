defmodule BotArmyJobScheduler.PulsePublisher do
  @moduledoc false

  use GenServer
  require Logger

  @health_interval_ms 30 * 1000
  @pulse_interval_ms 30 * 60 * 1000
  @service_name "job_scheduler"
  @envelope_source "bot_army_job_scheduler"

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @impl true
  def init(_opts) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)
    send(self(), :publish_health)
    send(self(), :publish_pulse)
    {:ok, %{started_at: started_at}}
  end

  @impl true
  def handle_info(:publish_health, state) do
    Task.start(fn -> publish_system_health(state) end)
    Process.send_after(self(), :publish_health, @health_interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(:publish_pulse, state) do
    Task.start(fn -> publish_pulse() end)
    Process.send_after(self(), :publish_pulse, @pulse_interval_ms)
    {:noreply, state}
  end

  defp publish_pulse do
    pulse = %{
      service: @service_name,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      health: :nominal,
      metrics: %{}
    }

    _ = BotArmyLibraryRuntime.NATS.Publisher.publish("bot.#{@service_name}.pulse", pulse)
    :ok
  end

  defp publish_system_health(%{started_at: started_at}) do
    tenant_id = System.get_env("BOT_ARMY_TENANT_ID") || BotArmyLibraryRuntime.Tenant.default_tenant_id()

    uptime_seconds =
      DateTime.diff(DateTime.utc_now() |> DateTime.truncate(:second), started_at, :second)

    case BotArmyLibraryRuntime.SynapseHealth.publish(
           source: @envelope_source,
           service: @service_name,
           tenant_id: tenant_id,
           health_signal: :nominal,
           uptime_seconds: max(uptime_seconds, 0)
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("[PulsePublisher] Failed to publish system.health: #{inspect(reason)}")
    end
  end
end
