defmodule BotArmyJobScheduler.NATS.Consumer do
  @moduledoc """
  NATS message consumer for the Job bot.

  Subscribes to NATS subjects matching Job message patterns:
  - `job.schedule.*` - Job scheduling events

  Messages are decoded using BotArmyCore.NATS.Decoder and routed to
  appropriate handlers based on the event type.

  ## Features

  - Automatic subscription to Job topics
  - Message decoding and validation
  - Event-based routing to handlers
  - Graceful error handling and recovery
  - Comprehensive logging

  ## Connection Management

  The consumer maintains a persistent NATS connection. If the connection
  is lost, it will attempt to reconnect with exponential backoff.
  """

  use GenServer
  require Logger

  @nats_url System.get_env("NATS_URL", "nats://localhost:4222")
  @reconnect_delay_ms 5000
  @max_reconnect_retries 10

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Callbacks

  @impl true
  def init(opts) do
    Logger.info("Starting Job NATS consumer")

    state = %{
      subscriptions: [],
      reconnect_attempt: 0,
      opts: opts
    }

    Logger.info("Job NATS consumer initialized, ready to receive messages from NATS broker")
    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5000) do
      {:ok, conn} ->
        BotArmyRuntime.NATS.Connection.subscribe_to_status()

        subjects = [
          "job.schedule.create",
          "job.schedule.update"
        ]

        subs =
          Enum.reduce_while(subjects, [], fn subject, acc ->
            case Gnat.sub(conn, self(), subject) do
              {:ok, sub} ->
                Logger.info("Job consumer subscribed to #{subject}")
                {:cont, [sub | acc]}

              {:error, reason} ->
                Logger.error("Failed to subscribe to #{subject}: #{inspect(reason)}")
                {:halt, acc}
            end
          end)

        if length(subs) == length(subjects) do
          {:noreply, %{state | subscriptions: subs}}
        else
          Logger.error("Failed to subscribe to all Job topics")
          Process.send_after(self(), :reconnect, @reconnect_delay_ms)
          {:noreply, state}
        end

      {:error, _reason} ->
        Logger.warning("NATS connection not ready, will retry")
        Process.send_after(self(), :reconnect, @reconnect_delay_ms)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:msg, msg}, state) do
    BotArmyRuntime.Tracing.with_consumer_span(msg.topic, Map.get(msg, :headers, []), fn ->
      Logger.debug("Received NATS message on subject: #{msg.topic}")

      case BotArmyCore.NATS.Decoder.decode(msg.body) do
        {:ok, decoded_message} ->
          route_message(decoded_message)

        {:error, reason} ->
          Logger.warning("Failed to decode message from #{msg.topic}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Attempting to reconnect to NATS")
    {:noreply, state, {:continue, :connect}}
  end

  @impl true
  def handle_info({:nats, :disconnected}, state) do
    Logger.warning("Disconnected from NATS, will reconnect")
    Process.send_after(self(), :reconnect, @reconnect_delay_ms)
    {:noreply, %{state | subscriptions: []}}
  end

  @impl true
  def handle_info({:nats, :connected}, state) do
    Logger.info("Reconnected to NATS, re-subscribing")
    {:noreply, state, {:continue, :connect}}
  end

  # Private functions

  @doc """
  Route decoded message to appropriate handler based on event type.
  """
  def route_message(message) do
    event = message["event"]

    case event do
      "job.schedule.create" -> BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
      "job.schedule.update" -> BotArmyJobScheduler.Handlers.ScheduleHandler.handle_update(message)
      _ -> Logger.debug("Unknown Job event type: #{event}")
    end
  end
end
