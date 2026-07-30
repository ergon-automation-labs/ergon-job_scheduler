defmodule BotArmyJobScheduler.Handlers.OpsHandler do
  @moduledoc """
  Handles ops.*.run tasks by invoking NATS subjects and collecting responses.

  Supports:
  - Target node filtering (only run on specific node)
  - Timeout handling with schema-compliant responses
  - Tracing via task_id
  """

  require Logger

  alias BotArmyLibraryRuntime.NATS.{Connection, Publisher}

  @doc """
  Handle an ops.task.run request.

  Expected message structure:
  ```json
  {
    "event": "ops.*.run",
    "payload": {
      "subject": "companion.heartbeat",
      "payload": {...},
      "target_node": "air",
      "timeout_seconds": 30,
      "task_id": "..."
    }
  }
  ```
  """
  def handle_run(message) do
    payload = message["payload"] || %{}
    subject = payload["subject"]
    target_payload = payload["payload"] || {}
    target_node = payload["target_node"]
    timeout_seconds = payload["timeout_seconds"] || 60
    task_id = payload["task_id"] || "no-task"

    unless subject do
      Logger.warning("Ops task missing required 'subject' field")
      return_error("Missing required field: subject", task_id)
      :ok
    end

    current_node = get_current_node()

    if target_node && target_node != current_node do
      Logger.debug(
        "Skipping ops task #{subject} - target=#{target_node}, current=#{current_node}"
      )

      :ok
    end

    execute_ops_task(subject, target_payload, timeout_seconds * 1000, task_id)
  end

  defp execute_ops_task(subject, payload, timeout_ms, task_id) do
    start_time = System.monotonic_time(:millisecond)

    case make_nats_request(subject, payload, timeout_ms) do
      {:ok, response} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.info("Ops task #{subject} completed in #{duration}ms, task_id=#{task_id}")

        publish_result(
          %{
            ok: true,
            data: %{
              subject: subject,
              status: "success",
              response: response,
              duration_ms: duration
            }
          },
          task_id
        )

      {:error, :timeout} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.warning("Ops task #{subject} timed out after #{duration}ms, task_id=#{task_id}")

        publish_result(
          %{
            ok: false,
            data: %{
              subject: subject,
              status: "timeout",
              duration_ms: duration
            },
            error: "Request timed out after #{timeout_ms}ms"
          },
          task_id
        )

      {:error, :no_responder} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.warning("Ops task #{subject} - no responder, task_id=#{task_id}")

        publish_result(
          %{
            ok: false,
            data: %{
              subject: subject,
              status: "no_responder",
              duration_ms: duration
            },
            error: "No responder for subject #{subject}"
          },
          task_id
        )

      {:error, reason} ->
        duration = System.monotonic_time(:millisecond) - start_time
        Logger.error("Ops task #{subject} failed: #{inspect(reason)}, task_id=#{task_id}")

        publish_result(
          %{
            ok: false,
            data: %{
              subject: subject,
              status: "error",
              duration_ms: duration
            },
            error: inspect(reason)
          },
          task_id
        )
    end

    :ok
  end

  defp make_nats_request(subject, payload, timeout_ms) do
    with {:ok, conn} <- Connection.get_connection() do
      case Gnat.request(conn, subject, Jason.encode!(payload), receive_timeout: timeout_ms) do
        {:ok, msg} ->
          case Jason.decode(msg.body) do
            {:ok, decoded} -> {:ok, decoded}
            {:error, _} -> {:ok, msg.body}
          end

        {:error, :timeout} ->
          {:error, :timeout}

        {:error, :no_responders} ->
          {:error, :no_responder}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp publish_result(result, task_id) do
    subject = "ops.task.result"

    envelope = %{
      "event" => "ops.task.result",
      "task_id" => task_id,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "payload" => result
    }

    case Publisher.publish(subject, envelope) do
      :ok ->
        Logger.debug("Published ops result to #{subject}, task_id=#{task_id}")

      {:error, reason} ->
        Logger.warning("Failed to publish ops result: #{inspect(reason)}, task_id=#{task_id}")
    end
  end

  defp return_error(error_msg, task_id) do
    publish_result(
      %{
        ok: false,
        data: %{
          subject: "unknown",
          status: "error"
        },
        error: error_msg
      },
      task_id
    )
  end

  defp get_current_node() do
    System.get_env("NODE_ID") ||
      System.get_env("HOSTNAME") ||
      node() |> Atom.to_string() |> String.split("@") |> List.first() ||
      "unknown"
  end
end
