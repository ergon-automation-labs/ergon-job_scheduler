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
  @schema_sync_command "ops.schema_sync.run"
  @para_daily_changed_command "ops.para_daily_changed.run"
  @gtd_para_export_command "ops.gtd_para_export.run"
  @daily_learning_podcast_command "ops.daily_learning_podcast.run"
  @para_inbox_media_ingest_command "ops.para_inbox_media_ingest.run"
  @synapse_scorecard_signals_command "ops.synapse_scorecard_signals.run"

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
    case schedule_value(schedule, "status", :status) do
      "active" ->
        case Crontab.CronExpression.parse(
               schedule_value(schedule, "cron_expression", :cron_expression)
             ) do
          {:ok, cron} ->
            # Check if the schedule is due to run
            last_run = parse_last_run(schedule_value(schedule, "last_run_at", :last_run_at), now)
            due = Crontab.DateChecker.matches_date?(cron, now)
            not_recently_run = DateTime.diff(now, last_run, :second) >= 60

            due and not_recently_run

          {:error, _} ->
            schedule_id = schedule_value(schedule, "id", :id)
            cron_expression = schedule_value(schedule, "cron_expression", :cron_expression)

            Logger.warning(
              "Invalid cron expression for schedule #{schedule_id}: #{cron_expression}"
            )

            false
        end

      _ ->
        false
    end
  end

  defp execute_schedule(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    schedule_title = schedule_value(schedule, "title", :title)
    Logger.info("Executing schedule #{schedule_id}: #{schedule_title}")

    case run_schedule_command(schedule) do
      :ok ->
        # Update last_run_at in the store and database
        payload = %{"last_run_at" => DateTime.utc_now()}
        BotArmyJobScheduler.ScheduleStore.update(schedule_id, payload)
        Logger.info("Schedule #{schedule_id} executed successfully")

      {:error, reason} ->
        Logger.error("Failed to execute schedule #{schedule_id}: #{inspect(reason)}")
    end
  end

  defp run_schedule_command(schedule) do
    case schedule_value(schedule, "command", :command) do
      @schema_sync_command -> run_schema_sync_job(schedule)
      @para_daily_changed_command -> run_para_daily_changed_job(schedule)
      @gtd_para_export_command -> run_gtd_para_export_job(schedule)
      @daily_learning_podcast_command -> run_daily_learning_podcast_job(schedule)
      @para_inbox_media_ingest_command -> run_para_inbox_media_ingest_job(schedule)
      @synapse_scorecard_signals_command -> run_synapse_scorecard_signals_job(schedule)
      _ -> publish_schedule_event(schedule)
    end
  end

  defp run_schema_sync_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")

    subject =
      System.get_env("JOB_SCHEDULER_SCHEMA_SYNC_SUBJECT", "synapse.context.schema_sync.report")

    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 900, 1) * 1000

    args = [
      "schema-sync-job",
      "PUBLISH=1",
      "SUBJECT=#{subject}"
    ]

    case System.cmd("make", args,
           cd: elixir_bots_dir,
           stderr_to_stdout: true,
           timeout: timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "Schema-sync job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "Schema-sync job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:schema_sync_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error("Schema-sync job raised for schedule #{rescue_schedule_id}: #{inspect(error)}")

      {:error, {:schema_sync_exception, error}}
  end

  defp run_gtd_para_export_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    para_root = System.get_env("PARA_SYNC_ROOT", "/Users/abby/Documents/personal_os")
    bot_drop = System.get_env("PARA_SYNC_BOT_DROP", "para-bot/inbox")
    port = System.get_env("PORT", "4222")
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 600, 1) * 1000

    args = [
      "gtd-para-export",
      "PARA_SYNC_ROOT=#{para_root}",
      "PARA_SYNC_BOT_DROP=#{bot_drop}",
      "PORT=#{port}"
    ]

    case System.cmd("make", args,
           cd: elixir_bots_dir,
           stderr_to_stdout: true,
           timeout: timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "GTD PARA export job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "GTD PARA export job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:gtd_para_export_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "GTD PARA export job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:gtd_para_export_exception, error}}
  end

  defp run_para_daily_changed_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")

    project_ref =
      System.get_env("JOB_SCHEDULER_PARA_PROJECT_REF", "fractional_contractor_readiness")

    date = Date.utc_today() |> Date.to_iso8601()
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 300, 1) * 1000
    port = System.get_env("PORT", "4222")

    args = [
      "bridge-para-daily-changed-smoke",
      "PROJECT_REF=#{project_ref}",
      "DATE=#{date}",
      "PORT=#{port}"
    ]

    case System.cmd("make", args,
           cd: elixir_bots_dir,
           stderr_to_stdout: true,
           timeout: timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "PARA daily-changed job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "PARA daily-changed job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:para_daily_changed_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "PARA daily-changed job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:para_daily_changed_exception, error}}
  end

  defp run_daily_learning_podcast_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    port = System.get_env("PORT", "4222")
    tenant_id = System.get_env("TENANT_ID", "00000000-0000-0000-0000-000000000001")
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 900, 1) * 1000
    dry_run = truthy_env?("LEARNING_PODCAST_DRY_RUN")
    invoke = not truthy_env?("LEARNING_PODCAST_NO_INVOKE")

    args = [
      "learning-podcast-job",
      "PORT=#{port}",
      "TENANT_ID=#{tenant_id}",
      "TIMEOUT_SECONDS=#{div(timeout_ms, 1000)}"
    ]

    args =
      if dry_run do
        args ++ ["DRY_RUN=1"]
      else
        args
      end

    args =
      if invoke do
        args
      else
        args ++ ["INVOKE=0"]
      end

    case System.cmd("make", args,
           cd: elixir_bots_dir,
           stderr_to_stdout: true,
           timeout: timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "Daily learning podcast job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "Daily learning podcast job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:daily_learning_podcast_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "Daily learning podcast job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:daily_learning_podcast_exception, error}}
  end

  defp run_para_inbox_media_ingest_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    para_root = System.get_env("PARA_SYNC_ROOT", "/Users/abby/Documents/personal_os")
    port = System.get_env("PORT", "4222")
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 900, 1) * 1000

    args = [
      "para-inbox-media-ingest-job",
      "PARA_SYNC_ROOT=#{para_root}",
      "PORT=#{port}",
      "TIMEOUT_SECONDS=#{div(timeout_ms, 1000)}"
    ]

    case System.cmd("make", args,
           cd: elixir_bots_dir,
           stderr_to_stdout: true,
           timeout: timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "PARA inbox media ingest job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "PARA inbox media ingest job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:para_inbox_media_ingest_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "PARA inbox media ingest job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:para_inbox_media_ingest_exception, error}}
  end

  defp run_synapse_scorecard_signals_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    port = System.get_env("PORT", System.get_env("NATS_PORT", "4222"))
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 3600, 1) * 1000

    args = [
      "synapse-scorecard-signals-with-para",
      "NATS_PORT=#{port}",
      "PORT=#{port}"
    ]

    case System.cmd("make", args,
           cd: elixir_bots_dir,
           stderr_to_stdout: true,
           timeout: timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "Synapse scorecard + PARA job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "Synapse scorecard + PARA job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:synapse_scorecard_signals_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "Synapse scorecard + PARA job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:synapse_scorecard_signals_exception, error}}
  end

  defp truthy_env?(key) do
    System.get_env(key, "false")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes"])
  end

  defp publish_schedule_event(schedule) do
    # Build the NATS message
    message = %{
      "schedule_id" => schedule_value(schedule, "id", :id),
      "title" => schedule_value(schedule, "title", :title),
      "command" => schedule_value(schedule, "command", :command),
      "timeout" => schedule_value(schedule, "timeout", :timeout),
      "cron_expression" => schedule_value(schedule, "cron_expression", :cron_expression)
    }

    # Publish to NATS - use the command to determine the subject
    subject = schedule_command_to_subject(schedule_value(schedule, "command", :command))

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

  defp parse_last_run(nil, now), do: DateTime.add(now, -1_000_000, :second)
  defp parse_last_run(%DateTime{} = last_run, _now), do: last_run

  defp parse_last_run(%NaiveDateTime{} = naive, _now) do
    DateTime.from_naive!(naive, "Etc/UTC")
  end

  defp parse_last_run(last_run, now) when is_binary(last_run) do
    case DateTime.from_iso8601(last_run) do
      {:ok, datetime, _} -> datetime
      _ -> DateTime.add(now, -1_000_000, :second)
    end
  end

  defp parse_last_run(_, now), do: DateTime.add(now, -1_000_000, :second)

  defp schedule_value(schedule, string_key, atom_key) do
    cond do
      is_map(schedule) and Map.has_key?(schedule, string_key) -> Map.get(schedule, string_key)
      is_map(schedule) and Map.has_key?(schedule, atom_key) -> Map.get(schedule, atom_key)
      true -> nil
    end
  end
end
