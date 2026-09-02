defmodule BotArmyJobScheduler.TelemetryHelper do
  @moduledoc """
  Helper module for emitting telemetry events and metrics for scheduled job execution.

  Emits:
  - Telemetry spans for OpenTelemetry tracing
  - Structured logs with timing information
  - NATS completion events for observability
  """

  require Logger

  @doc """
  Execute a job with telemetry instrumentation.

  Records execution time, status, and emits events to NATS.

  Returns: {:ok, result, elapsed_ms} or {:error, reason, elapsed_ms}
  """
  def execute_with_telemetry(schedule, job_name, job_func) do
    schedule_id = Map.get(schedule, "id") || "unknown"
    start_time = System.monotonic_time(:millisecond)

    # Emit telemetry span for OpenTelemetry tracing
    :telemetry.execute(
      [:job_scheduler, :job, :start],
      %{system_time: System.system_time(:millisecond)},
      %{
        schedule_id: schedule_id,
        job_name: job_name,
        title: Map.get(schedule, "title", "unknown")
      }
    )

    result = job_func.()
    elapsed_ms = System.monotonic_time(:millisecond) - start_time

    # Emit completion telemetry
    case result do
      :ok ->
        emit_success_telemetry(schedule_id, job_name, elapsed_ms, schedule)
        emit_nats_completion_event(schedule, :success, elapsed_ms, "")
        {:ok, elapsed_ms}

      {:error, reason} ->
        emit_failure_telemetry(schedule_id, job_name, elapsed_ms, reason, schedule)
        emit_nats_completion_event(schedule, :failure, elapsed_ms, inspect(reason))
        {:error, reason, elapsed_ms}
    end
  end

  defp emit_success_telemetry(schedule_id, job_name, elapsed_ms, schedule) do
    Logger.info("Job execution completed",
      schedule_id: schedule_id,
      job_name: job_name,
      elapsed_ms: elapsed_ms,
      status: :success,
      title: Map.get(schedule, "title")
    )

    :telemetry.execute(
      [:job_scheduler, :job, :complete],
      %{
        duration_ms: elapsed_ms,
        system_time: System.system_time(:millisecond)
      },
      %{
        schedule_id: schedule_id,
        job_name: job_name,
        status: :success,
        title: Map.get(schedule, "title", "unknown")
      }
    )
  end

  defp emit_failure_telemetry(schedule_id, job_name, elapsed_ms, reason, schedule) do
    Logger.error("Job execution failed",
      schedule_id: schedule_id,
      job_name: job_name,
      elapsed_ms: elapsed_ms,
      status: :failure,
      error: inspect(reason),
      title: Map.get(schedule, "title")
    )

    :telemetry.execute(
      [:job_scheduler, :job, :error],
      %{
        duration_ms: elapsed_ms,
        system_time: System.system_time(:millisecond)
      },
      %{
        schedule_id: schedule_id,
        job_name: job_name,
        status: :failure,
        error: inspect(reason),
        title: Map.get(schedule, "title", "unknown")
      }
    )
  end

  defp emit_nats_completion_event(schedule, status, elapsed_ms, error_msg) do
    message = %{
      "schedule_id" => Map.get(schedule, "id"),
      "title" => Map.get(schedule, "title"),
      "command" => Map.get(schedule, "command"),
      "status" => Atom.to_string(status),
      "elapsed_ms" => elapsed_ms,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "error" => if(status == :failure, do: error_msg, else: nil)
    }

    subject = "job.schedule.completed:#{Atom.to_string(status)}"

    case BotArmyLibraryRuntime.NATS.Publisher.publish(subject, message) do
      {:ok, _} ->
        Logger.debug("Published job completion event",
          subject: subject,
          schedule_id: Map.get(schedule, "id")
        )

      {:error, reason} ->
        Logger.warning("Failed to publish job completion event",
          subject: subject,
          error: inspect(reason)
        )
    end
  end
end
