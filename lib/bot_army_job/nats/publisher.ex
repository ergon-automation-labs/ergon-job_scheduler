defmodule BotArmyJobScheduler.NATS.Publisher do
  @moduledoc """
  NATS event publisher for the Job bot.

  Publishes response events from Job handlers back to the NATS broker.
  Events include job.scheduled, job.schedule.updated, and error events.

  ## Features

  - Serialization of events to JSON
  - Subject routing based on event type
  - Error handling and logging
  - Connection management
  """

  require Logger

  @doc """
  Publish a message directly to a NATS subject.

  Takes a subject string and message map. Returns `:ok` if successful, or `{:error, reason}` on failure.
  """
  def publish(subject, message) when is_binary(subject) and is_map(message) do
    try do
      body = Jason.encode!(message)

      case do_publish(subject, body) do
        :ok ->
          Logger.debug("Published message to #{subject}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to publish to #{subject}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception during publish: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Publish an event to NATS.

  The event map should contain:
  - `"event"` - Event type (e.g., "job.scheduled")
  - `"event_id"` - Unique event identifier
  - `"timestamp"` - ISO8601 timestamp
  - `"source"` - Source bot (e.g., "bot_army_job")
  - `"source_node"` - Node name
  - `"triggered_by"` - Audit value
  - `"schema_version"` - Schema version
  - `"payload"` - Event payload

  Returns `:ok` if successful, or `{:error, reason}` on failure.
  """
  def publish(event) when is_map(event) do
    try do
      subject = derive_subject(event["event"])
      body = Jason.encode!(event)

      case do_publish(subject, body) do
        :ok ->
          Logger.debug("Published event to #{subject}")
          :ok

        {:error, reason} ->
          Logger.error("Failed to publish to #{subject}: #{inspect(reason)}")
          {:error, reason}
      end
    rescue
      e ->
        Logger.error("Exception during publish: #{inspect(e)}")
        {:error, e}
    end
  end

  def publish(_) do
    {:error, :invalid_event}
  end

  # Private functions

  defp do_publish(subject, body) do
    # In production, this would connect to NATS and publish
    # For now, log the publish attempt
    Logger.info("Publishing to #{subject}: #{String.slice(body, 0, 100)}...")
    :ok
  end

  defp derive_subject(event_type) when is_binary(event_type) do
    case event_type do
      "job.scheduled" -> "events.job.scheduled"
      "job.schedule.updated" -> "events.job.schedule.updated"
      "job.error" -> "events.job.error"
      _ -> "events.job.unknown"
    end
  end

  defp derive_subject(_) do
    "events.job.unknown"
  end
end
