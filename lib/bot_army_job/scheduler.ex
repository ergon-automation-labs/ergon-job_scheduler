defmodule BotArmyJobScheduler.Scheduler do
  @moduledoc """
  Scheduler GenServer that runs due scheduled tasks.

  Periodically checks the schedule store for tasks due to run,
  publishes them to NATS, and updates their last_run_at timestamp.

  Runs every 60 seconds by default.
  """

  use GenServer
  require Logger

  @server __MODULE__
  # Check every minute
  @check_interval_ms 60_000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting JobScheduler - checking every #{@check_interval_ms}ms")
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_schedules, state) do
    check_and_run_due_schedules()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_schedules, @check_interval_ms)
  end

  defp check_and_run_due_schedules do
    try do
      now = DateTime.utc_now()

      case BotArmyJobScheduler.ScheduleStore.list() do
        {:ok, schedules} ->
          schedules
          |> Enum.filter(&is_due?(&1, now))
          |> Enum.each(&execute_schedule/1)

        {:error, reason} ->
          Logger.error("Failed to list schedules: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.error("Error checking schedules: #{inspect(error)}")
    end
  end

  defp is_due?(schedule, now) do
    case schedule.status do
      "active" ->
        case Crontab.CronExpression.parse(schedule.cron_expression) do
          {:ok, cron} ->
            # Check if the schedule is due to run
            last_run = schedule.last_run_at || DateTime.add(now, -1_000_000, :second)
            due = Crontab.DateChecker.matches_date?(cron, now)
            not_recently_run = DateTime.diff(now, last_run, :second) >= 60

            due and not_recently_run

          {:error, _} ->
            Logger.warn(
              "Invalid cron expression for schedule #{schedule.id}: #{schedule.cron_expression}"
            )

            false
        end

      _ ->
        false
    end
  end

  defp execute_schedule(schedule) do
    Logger.info("Executing schedule #{schedule.id}: #{schedule.title}")

    case publish_schedule_event(schedule) do
      :ok ->
        # Update last_run_at in the store and database
        payload = %{"last_run_at" => DateTime.utc_now()}
        BotArmyJobScheduler.ScheduleStore.update(schedule.id, payload)
        Logger.info("Schedule #{schedule.id} executed successfully")

      {:error, reason} ->
        Logger.error("Failed to execute schedule #{schedule.id}: #{inspect(reason)}")
    end
  end

  defp publish_schedule_event(schedule) do
    # Build the NATS message
    message = %{
      "schedule_id" => schedule.id,
      "title" => schedule.title,
      "command" => schedule.command,
      "timeout" => schedule.timeout,
      "cron_expression" => schedule.cron_expression
    }

    # Publish to NATS - use the command to determine the subject
    subject = schedule_command_to_subject(schedule.command)

    case BotArmyRuntime.NATS.Publisher.publish(subject, message) do
      {:ok, _subject} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_command_to_subject(command) do
    case command do
      "job.discovery.scan" -> "job.discovery.scan"
      "job.digest.generate" -> "job.digest.generate"
      other -> "job.schedule.execute:#{other}"
    end
  end
end
