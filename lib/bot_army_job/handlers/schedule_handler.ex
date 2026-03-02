defmodule BotArmyJob.Handlers.ScheduleHandler do
  @moduledoc """
  Handles job scheduling events for the Job bot.

  This module processes incoming job schedule messages:
  - `job.schedule.create` - Create a new job schedule
  - `job.schedule.update` - Update job schedule

  Each operation validates the input, stores the schedule, and publishes
  corresponding response events.

  ## Dependencies

  - `BotArmyJob.ScheduleStore` - Persistent schedule storage
  - `BotArmyJob.NATS.Publisher` - Event publishing
  """

  require Logger

  @doc """
  Handle job schedule creation event.

  Validates the schedule data, stores it, and publishes a job.scheduled event.

  Returns `:ok` if successful, or logs errors on failure.
  """
  def handle_create(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_create_payload(payload) do
      :ok ->
        case BotArmyJob.ScheduleStore.create(payload) do
          {:ok, schedule} ->
            Logger.info("Job schedule created: schedule_id=#{schedule["id"]}, event_id=#{event_id}")
            publish_event("job.scheduled", payload, schedule, event_id, message)

          {:error, reason} ->
            Logger.error("Failed to create job schedule: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to create job schedule")
        end

      {:error, reason} ->
        Logger.warning("Invalid job schedule payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid job schedule data")
    end
  end

  @doc """
  Handle job schedule update event.

  Validates the update data, applies it, and publishes a job.schedule.updated event.
  """
  def handle_update(message) do
    event_id = message["event_id"]
    payload = message["payload"]

    case validate_update_payload(payload) do
      :ok ->
        schedule_id = payload["schedule_id"]

        case BotArmyJob.ScheduleStore.update(schedule_id, payload) do
          {:ok, schedule} ->
            Logger.info("Job schedule updated: schedule_id=#{schedule_id}, event_id=#{event_id}")
            publish_event("job.schedule.updated", payload, schedule, event_id, message)

          {:error, reason} ->
            Logger.error("Failed to update job schedule #{schedule_id}: #{inspect(reason)}")
            publish_error(event_id, reason, "Failed to update job schedule")
        end

      {:error, reason} ->
        Logger.warning("Invalid job schedule update payload: #{inspect(reason)}")
        publish_error(event_id, reason, "Invalid job schedule data")
    end
  end

  # Private functions

  defp validate_create_payload(payload) when is_map(payload) do
    with :ok <- require_field(payload, "job_name"),
         :ok <- require_field(payload, "cron_expression") do
      :ok
    end
  end

  defp validate_create_payload(_), do: {:error, :invalid_payload}

  defp validate_update_payload(payload) when is_map(payload) do
    require_field(payload, "schedule_id")
  end

  defp validate_update_payload(_), do: {:error, :invalid_payload}

  defp require_field(payload, field) do
    case payload do
      %{^field => value} when value not in [nil, ""] -> :ok
      _ -> {:error, {:missing_field, field}}
    end
  end

  defp publish_event(event_type, payload, schedule, event_id, original_message) do
    event_data = %{
      "event" => event_type,
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_job",
      "source_node" => get_node_name(),
      "triggered_by" => "job.bot",
      "schema_version" => "1.0",
      "payload" => %{
        "schedule" => schedule,
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyJob.NATS.Publisher.publish(event_data) do
      :ok -> Logger.debug("Published event: #{event_type}")
      {:error, reason} -> Logger.error("Failed to publish event: #{inspect(reason)}")
    end
  end

  defp publish_error(event_id, reason, message) do
    error_event = %{
      "event" => "job.error",
      "event_id" => UUID.uuid4(),
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "bot_army_job",
      "source_node" => get_node_name(),
      "triggered_by" => "job.bot",
      "schema_version" => "1.0",
      "payload" => %{
        "error" => message,
        "reason" => inspect(reason),
        "triggered_by_event_id" => event_id
      }
    }

    case BotArmyJob.NATS.Publisher.publish(error_event) do
      :ok -> Logger.debug("Published error event")
      {:error, err} -> Logger.error("Failed to publish error: #{inspect(err)}")
    end
  end

  defp get_node_name do
    node() |> Atom.to_string()
  end
end
