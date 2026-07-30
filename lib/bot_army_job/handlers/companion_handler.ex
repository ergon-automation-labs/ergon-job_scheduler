defmodule BotArmyJobScheduler.Handlers.CompanionHandler do
  @moduledoc """
  Handles companion.heartbeat NATS requests.

  Executes the companion heartbeat script (logs system state + LLM reflection)
  and returns the result.
  """

  require Logger

  alias BotArmyLibraryRuntime.NATS.Publisher

  def handle_heartbeat(message) do
    start_time = System.monotonic_time(:millisecond)

    case execute_heartbeat() do
      {:ok, output} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.info("Companion heartbeat completed in #{duration}ms")

        result = %{
          ok: true,
          data: %{
            status: "success",
            output: output,
            duration_ms: duration
          }
        }

        publish_event(result)
        {:reply, result}

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("Companion heartbeat failed: #{inspect(reason)}")

        result = %{
          ok: false,
          data: %{
            status: "error",
            duration_ms: duration
          },
          error: inspect(reason)
        }

        publish_event(result)
        {:reply, result}
    end
  end

  defp execute_heartbeat do
    script_path = "/Users/abby/code/elixir_bots/scripts/companion-heartbeat.sh"

    case System.cmd("bash", [script_path], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, output}

      {output, exit_code} ->
        {:error, "Script exited with code #{exit_code}: #{output}"}
    end
  end

  defp publish_event(result) do
    envelope = %{
      "event" => "companion.heartbeat.complete",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "payload" => result
    }

    Publisher.publish("companion.events", envelope)
  end
end
