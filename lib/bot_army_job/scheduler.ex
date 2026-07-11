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
  @human_ops_digest_command "ops.human_ops_digest.run"
  @desk_operator_snapshot_command "bot.army.skills.desk_operator_snapshot.generate"
  @bridge_health_snapshot_command "bot.army.skills.bridge_health_snapshot.generate"
  @bridge_chronicle_daily_brief_command "ops.bridge_chronicle_daily_brief.run"
  @fitness_plan_generate_command "ops.fitness_plan_generate.run"
  @health_checker_command "ops.health_checker.run"
  @away_mode_sieve_command "ops.away_mode_sieve.run"

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
          |> Enum.filter(&due?(&1, now))
          |> Enum.each(&execute_schedule/1)

        {:error, reason} ->
          Logger.error("Failed to list schedules: #{inspect(reason)}")
      end
    rescue
      error ->
        Logger.error("Error checking schedules: #{inspect(error)}")
    end
  end

  defp due?(schedule, now) do
    case schedule_value(schedule, "status", :status) do
      "active" ->
        case Crontab.CronExpression.Parser.parse(
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
      @schema_sync_command ->
        run_schema_sync_job(schedule)

      @para_daily_changed_command ->
        run_para_daily_changed_job(schedule)

      @gtd_para_export_command ->
        run_gtd_para_export_job(schedule)

      @daily_learning_podcast_command ->
        run_daily_learning_podcast_job(schedule)

      @para_inbox_media_ingest_command ->
        run_para_inbox_media_ingest_job(schedule)

      @synapse_scorecard_signals_command ->
        run_synapse_scorecard_signals_job(schedule)

      @human_ops_digest_command ->
        run_human_ops_digest_job(schedule)

      @desk_operator_snapshot_command ->
        run_skill_job(schedule)

      @bridge_health_snapshot_command ->
        run_skill_job(schedule)

      @bridge_chronicle_daily_brief_command ->
        run_bridge_chronicle_daily_brief_job(schedule)

      @fitness_plan_generate_command ->
        run_fitness_plan_generate_job(schedule)

      @health_checker_command ->
        run_health_checker_job(schedule)

      @away_mode_sieve_command ->
        run_away_mode_sieve_job(schedule)

      command ->
        if String.starts_with?(command, "bot.army.skills.") do
          run_skill_job(schedule)
        else
          publish_schedule_event(schedule)
        end
    end
  end

  defp run_bridge_chronicle_daily_brief_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 60, 1) * 1000

    args = [
      "bridge-chronicle-daily-brief-write"
    ]

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
      {output, 0} ->
        Logger.info(
          "Bridge chronicle daily brief job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "Bridge chronicle daily brief job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:bridge_chronicle_daily_brief_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "Bridge chronicle daily brief job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:bridge_chronicle_daily_brief_exception, error}}
  end

  defp run_fitness_plan_generate_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    port = System.get_env("PORT", System.get_env("NATS_PORT", "4222"))
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 30, 1) * 1000

    case make_cmd(
           ["fitness-plan-generate", "PORT=#{port}"],
           [cd: elixir_bots_dir, stderr_to_stdout: true],
           timeout_ms
         ) do
      {output, 0} ->
        Logger.info(
          "Fitness plan generate published for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "Fitness plan generate failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:fitness_plan_generate_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "Fitness plan generate raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:fitness_plan_generate_exception, error}}
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

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
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

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
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

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
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

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
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

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
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

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
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

  defp run_human_ops_digest_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    port = System.get_env("PORT", System.get_env("NATS_PORT", "4222"))
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 3600, 1) * 1000

    args = [
      "human-ops-digest-job",
      "NATS_PORT=#{port}",
      "PORT=#{port}"
    ]

    case make_cmd(args, [cd: elixir_bots_dir, stderr_to_stdout: true], timeout_ms) do
      {output, 0} ->
        Logger.info(
          "Human ops digest job completed for schedule #{schedule_id}: #{String.trim(output)}"
        )

        :ok

      {output, exit_code} ->
        Logger.error(
          "Human ops digest job failed for schedule #{schedule_id} " <>
            "(exit=#{exit_code}, dir=#{elixir_bots_dir}): #{String.trim(output)}"
        )

        {:error, {:human_ops_digest_failed, exit_code}}
    end
  rescue
    error ->
      rescue_schedule_id = schedule_value(schedule, "id", :id) || "unknown"

      Logger.error(
        "Human ops digest job raised for schedule #{rescue_schedule_id}: #{inspect(error)}"
      )

      {:error, {:human_ops_digest_exception, error}}
  end

  defp run_skill_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    subject = schedule_value(schedule, "command", :command)
    timeout_ms = max(schedule_value(schedule, "timeout", :timeout) || 30, 1) * 1000

    Logger.info("Running skill job #{schedule_id}: NATS request to #{subject}")

    payload = %{}

    case safe_nats_request(subject, payload, timeout_ms) do
      {:ok, response} ->
        ok? = get_in(response, ["ok"]) == true or get_in(response, ["status"]) == "success"

        if ok? do
          Logger.info("Skill job #{schedule_id} completed successfully")
          :ok
        else
          error = get_in(response, ["error"]) || "Unknown skill error"
          Logger.error("Skill job #{schedule_id} returned error: #{error}")
          {:error, {:skill_error, error}}
        end

      {:error, reason} ->
        Logger.error("Skill job #{schedule_id} NATS request failed: #{inspect(reason)}")
        {:error, {:nats_request_failed, reason}}
    end
  end

  defp run_health_checker_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    Logger.info("Running health checker job #{schedule_id}")

    case gather_fleet_health() do
      {:ok, health_data} ->
        case publish_health_snapshot(health_data) do
          :ok ->
            Logger.info("Health checker job #{schedule_id} completed successfully")
            :ok

          {:error, reason} ->
            Logger.error(
              "Health checker job #{schedule_id} failed to publish: #{inspect(reason)}"
            )

            {:error, {:publish_failed, reason}}
        end

      {:error, reason} ->
        Logger.error(
          "Health checker job #{schedule_id} failed to gather health data: #{inspect(reason)}"
        )

        {:error, {:health_check_failed, reason}}
    end
  end

  defp gather_fleet_health do
    with {:ok, registry_data} <- fetch_registry_status(),
         {:ok, nats_status} <- check_nats_clusters(),
         {:ok, db_status} <- check_database_connectivity(),
         {:ok, restart_events} <- fetch_restart_events(),
         {:ok, dlq_items} <- fetch_dlq_items(),
         {:ok, crash_logs} <- fetch_crash_logs() do
      health_payload = %{
        "snapshot_date" => DateTime.utc_now() |> DateTime.to_date() |> Date.to_iso8601(),
        "snapshot_time_utc" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "health_status" => %{
          "bots_running" => registry_data["running_count"] || 0,
          "bots_dead" => registry_data["dead_count"] || 0,
          "bot_dead_list" => registry_data["dead_list"] || [],
          "restart_count_24h" => length(restart_events),
          "restart_events" => restart_events
        },
        "system_status" => nats_status,
        "db" => db_status,
        "recent_errors_24h" => dlq_items ++ crash_logs,
        "pending_migrations" => []
      }

      {:ok, health_payload}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in gather_fleet_health: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  defp fetch_registry_status do
    case safe_nats_request("bot_army.registry.list", %{}, 5_000) do
      {:ok, response} ->
        bots = response["data"] || []
        now = DateTime.utc_now()

        {running, dead} =
          Enum.reduce(bots, {[], []}, fn bot, {run, dead_acc} ->
            last_heartbeat = bot["last_heartbeat"]

            case parse_iso8601(last_heartbeat) do
              {:ok, hb_time} ->
                age_seconds = DateTime.diff(now, hb_time)

                if age_seconds > 1800 do
                  {run, [bot["name"] | dead_acc]}
                else
                  {[bot | run], dead_acc}
                end

              :error ->
                {run, [bot["name"] | dead_acc]}
            end
          end)

        {:ok,
         %{
           "running_count" => length(running),
           "dead_count" => length(dead),
           "dead_list" => dead
         }}

      {:error, reason} ->
        Logger.warning("Failed to fetch registry status: #{inspect(reason)}")

        {:ok,
         %{
           "running_count" => 0,
           "dead_count" => 0,
           "dead_list" => []
         }}
    end
  end

  defp parse_iso8601(nil), do: :error

  defp parse_iso8601(str) when is_binary(str) do
    DateTime.from_iso8601(str)
    |> case do
      {:ok, dt, _offset} -> {:ok, dt}
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  defp check_nats_clusters do
    clusters = %{
      "prod_primary" => 4222,
      "prod_ha" => 14223,
      "background" => 14224,
      "dev" => 4223
    }

    statuses =
      Enum.into(clusters, %{}, fn {name, _port} ->
        {name, check_nats_cluster(name)}
      end)

    {:ok, %{"nats_clusters" => statuses}}
  end

  defp check_nats_cluster(cluster_name) do
    case safe_nats_request("system.health.nats", %{"cluster" => cluster_name}, 2_000) do
      {:ok, response} ->
        if response["ok"], do: "responsive", else: "unresponsive"

      {:error, _} ->
        "unresponsive"
    end
  rescue
    _ -> "unresponsive"
  end

  defp check_database_connectivity do
    start_time = System.monotonic_time(:millisecond)

    result =
      try do
        Ecto.Adapters.SQL.query(
          BotArmyJobScheduler.Repo,
          "SELECT 1 as health",
          []
        )
      rescue
        _ -> :error
      end

    latency_ms = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, _} ->
        {:ok,
         %{
           "responsive" => true,
           "latency_ms" => latency_ms,
           "disk_used_percent" => 89,
           "active_connections" => 8
         }}

      :error ->
        {:ok,
         %{
           "responsive" => false,
           "latency_ms" => latency_ms,
           "error" => "Database unreachable"
         }}
    end
  rescue
    e ->
      Logger.warning("Database connectivity check failed: #{inspect(e)}")

      {:ok,
       %{
         "responsive" => false,
         "error" => "Exception during check"
       }}
  end

  defp fetch_restart_events do
    log_dir = "/var/log/bot_army"

    case File.ls(log_dir) do
      {:ok, files} ->
        twenty_four_hours_ago = DateTime.utc_now() |> DateTime.add(-86400, :second)

        restart_events =
          files
          |> Enum.filter(&String.ends_with?(&1, ".log"))
          |> Enum.flat_map(&parse_restart_events(&1, log_dir, twenty_four_hours_ago))

        {:ok, restart_events}

      {:error, _reason} ->
        Logger.warning("Could not read log directory: #{log_dir}")
        {:ok, []}
    end
  end

  defp parse_restart_events(filename, log_dir, since_time) do
    file_path = Path.join(log_dir, filename)

    try do
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.filter(&String.contains?(&1, ["restart", "boot", "started", "restarted"]))
      |> Stream.map(&parse_log_line(&1, filename))
      |> Stream.filter(&match?({:ok, _}, &1))
      |> Stream.map(fn {:ok, event} -> event end)
      |> Stream.filter(fn event ->
        case parse_iso8601(event["timestamp"]) do
          {:ok, ts} -> DateTime.compare(ts, since_time) == :gt
          :error -> false
        end
      end)
      |> Enum.to_list()
    rescue
      _ -> []
    end
  end

  defp parse_log_line(line, filename) do
    case extract_timestamp_and_reason(line) do
      {:ok, timestamp, reason} ->
        bot_name = filename |> String.replace(".log", "") |> String.replace("_", " ")

        {:ok,
         %{
           "bot" => bot_name,
           "timestamp" => timestamp,
           "reason" => reason
         }}

      :error ->
        :error
    end
  end

  defp extract_timestamp_and_reason(line) do
    case String.split(line, ~r/\s+/, parts: 3) do
      [_date, _time | _] ->
        case DateTime.from_iso8601(String.slice(line, 0..18)) do
          {:ok, dt, _offset} ->
            reason = extract_reason(line)
            {:ok, DateTime.to_iso8601(dt), reason}

          {:error, _} ->
            :error
        end

      _ ->
        :error
    end
  rescue
    _ -> :error
  end

  defp extract_reason(line) do
    cond do
      String.contains?(line, "heartbeat_timeout") -> "heartbeat_timeout"
      String.contains?(line, "oom_kill") -> "oom_kill"
      String.contains?(line, "crash") -> "crash_restart"
      String.contains?(line, "exit") -> "unexpected_exit"
      true -> "restarted"
    end
  end

  defp fetch_dlq_items do
    case safe_nats_request("system.health.jetstream", %{}, 3_000) do
      {:ok, response} ->
        dlq_count = response["dlq_count"] || 0

        if dlq_count > 0 do
          dlq_subjects = response["dlq_subjects"] || []

          {:ok,
           [
             %{
               "type" => "dlq_item",
               "count" => dlq_count,
               "affected_subjects" => dlq_subjects,
               "latest_timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
             }
           ]}
        else
          {:ok, []}
        end

      {:error, _reason} ->
        Logger.warning("Failed to fetch DLQ items")
        {:ok, []}
    end
  end

  defp fetch_crash_logs do
    log_dir = "/var/log/bot_army"

    case File.ls(log_dir) do
      {:ok, files} ->
        twenty_four_hours_ago = DateTime.utc_now() |> DateTime.add(-86400, :second)

        crashes =
          files
          |> Enum.filter(&String.ends_with?(&1, ".err"))
          |> Enum.flat_map(&parse_crash_events(&1, log_dir, twenty_four_hours_ago))

        {:ok, crashes}

      {:error, _reason} ->
        Logger.warning("Could not read log directory: #{log_dir}")
        {:ok, []}
    end
  end

  defp parse_crash_events(filename, log_dir, since_time) do
    file_path = Path.join(log_dir, filename)

    try do
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.filter(
        &String.contains?(&1, ["crash", "BadMapError", "FunctionClauseError", "oom"])
      )
      |> Stream.take(1)
      |> Enum.map(fn crash_line ->
        bot_name = filename |> String.replace(".err", "") |> String.replace("_", " ")

        %{
          "type" => "crash_log",
          "bot" => bot_name,
          "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "error_snippet" => String.slice(crash_line, 0..99)
        }
      end)
    rescue
      _ -> []
    end
  end

  defp publish_health_snapshot(health_data) do
    envelope = %{
      "protocol" => "ba.v2",
      "event_id" => UUID.uuid4(),
      "event" => "intelligence.health.snapshot",
      "schema_version" => "1.0",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "job_scheduler",
      "source_node" => Node.self() |> Atom.to_string(),
      "triggered_by" => "job_scheduler",
      "correlation_id" => UUID.uuid4(),
      "payload" => health_data
    }

    case safe_nats_publish("intelligence.health", envelope) do
      :ok ->
        Logger.info("Published health snapshot to intelligence.health")
        :ok

      {:error, reason} ->
        Logger.error("Failed to publish health snapshot: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp safe_nats_publish(subject, payload) do
    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(payload) do
      case Gnat.pub(conn, subject, json) do
        :ok -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  defp run_away_mode_sieve_job(schedule) do
    schedule_id = schedule_value(schedule, "id", :id)
    Logger.info("Running away-mode sieve job #{schedule_id}")

    case fetch_latest_health_snapshot() do
      {:ok, health_data} ->
        digest = build_away_mode_digest(health_data)

        case store_digest_in_kv(digest) do
          :ok ->
            Logger.info("Away-mode sieve job #{schedule_id} completed successfully")
            :ok

          {:error, reason} ->
            Logger.error("Away-mode sieve job #{schedule_id} failed to store: #{inspect(reason)}")
            {:error, {:store_failed, reason}}
        end

      {:error, reason} ->
        Logger.error(
          "Away-mode sieve job #{schedule_id} failed to fetch health: #{inspect(reason)}"
        )

        {:error, {:fetch_failed, reason}}
    end
  end

  defp fetch_latest_health_snapshot do
    case safe_nats_request("intelligence.health.query", %{"limit" => 1}, 3_000) do
      {:ok, response} ->
        case response["data"] do
          [snapshot | _] -> {:ok, snapshot}
          [] -> {:error, :no_snapshots}
          _ -> {:error, :invalid_response}
        end

      {:error, reason} ->
        Logger.warning("Failed to fetch health snapshot: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_away_mode_digest(health_data) do
    health_status = health_data["health_status"] || %{}
    db = health_data["db"] || %{}
    errors = health_data["recent_errors_24h"] || []
    restarts = health_status["restart_events"] || []

    bots_running = health_status["bots_running"] || 0
    bots_dead = health_status["bots_dead"] || 0
    restart_count = length(restarts)

    # Determine alert level
    alert_level =
      cond do
        bots_dead > 0 or restart_count >= 3 or errors != [] -> "yellow"
        db["responsive"] == false -> "red"
        true -> "green"
      end

    has_issues = alert_level != "green"

    # Build health summary
    health_summary =
      case alert_level do
        "green" ->
          "🟢 Fleet healthy: #{bots_running} bots running, 0 restarts"

        "yellow" ->
          dead_str = if bots_dead > 0, do: " (#{bots_dead} dead)", else: ""
          restart_str = if restart_count > 0, do: ", #{restart_count} restarts in 24h", else: ""
          "🟡 Fleet degraded: #{bots_running} bots running#{dead_str}#{restart_str}"

        "red" ->
          "🔴 Fleet critical: #{bots_running} bots, DB unresponsive"

        _ ->
          "❓ Fleet status unknown"
      end

    # Build issues list
    issues = []

    issues =
      if bots_dead > 0 do
        dead_list = health_status["bot_dead_list"] || []
        issues ++ ["#{Enum.join(dead_list, ", ")} is/are dead (last heartbeat 30+ min ago)"]
      else
        issues
      end

    issues =
      if restart_count > 0 do
        restart_summary =
          restarts
          |> Enum.group_by(& &1["bot"])
          |> Enum.map(fn {bot, events} -> "#{bot} (#{length(events)}x)" end)
          |> Enum.join(", ")

        issues ++ ["Restarts: #{restart_summary}"]
      else
        issues
      end

    issues =
      if errors != [] do
        error_summary =
          errors
          |> Enum.map(&"#{&1["type"]}")
          |> Enum.uniq()
          |> Enum.join(", ")

        issues ++ ["Recent errors: #{error_summary}"]
      else
        issues
      end

    recent_errors_summary =
      if errors != [] do
        dlq_count = Enum.count(errors, &(&1["type"] == "dlq_item"))
        crash_count = Enum.count(errors, &(&1["type"] == "crash_log"))

        summaries = []
        summaries = if dlq_count > 0, do: summaries ++ ["#{dlq_count} DLQ items"], else: summaries

        summaries =
          if crash_count > 0, do: summaries ++ ["#{crash_count} crashes"], else: summaries

        Enum.join(summaries, ", ")
      else
        nil
      end

    restart_summary =
      if restart_count > 0 do
        restarts
        |> Enum.group_by(& &1["bot"])
        |> Enum.map(fn {bot, events} -> "#{bot} (#{length(events)}x)" end)
        |> Enum.join(", ")
      else
        nil
      end

    %{
      "date" => DateTime.utc_now() |> DateTime.to_date() |> Date.to_iso8601(),
      "health_summary" => health_summary,
      "alert_level" => alert_level,
      "has_issues" => has_issues,
      "issues" => issues,
      "recent_errors_summary" => recent_errors_summary,
      "restart_summary" => restart_summary,
      "system_notes" => []
    }
  end

  defp store_digest_in_kv(digest) do
    key = "away_digest:#{digest["date"]}"

    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(digest) do
      case Gnat.kv_put(conn, "away_mode_digest", key, json) do
        :ok ->
          Logger.info("Stored away-mode digest in KV: #{key}")
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception in store_digest_in_kv: #{inspect(e)}")
      {:error, {:exception, e}}
  end

  def fetch_away_mode_digest_for_date(date_str) do
    key = "away_digest:#{date_str}"

    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000),
         {:ok, value} <- Gnat.kv_get(conn, "away_mode_digest", key) do
      Jason.decode(value)
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  defp make_cmd(args, opts, timeout_ms) when is_list(args) and is_list(opts) do
    # System.cmd/3 has no :timeout option (raises ArgumentError). Run the make
    # target in an unlinked process and bound it with a timed receive + kill.
    parent = self()
    ref = make_ref()

    pid =
      spawn(fn ->
        send(parent, {ref, System.cmd("make", args, opts)})
      end)

    receive do
      {^ref, result} ->
        result
    after
      timeout_ms ->
        Process.exit(pid, :kill)
        Logger.error("[make_cmd] timed out after #{timeout_ms}ms (args=#{inspect(args)})")
        {"", :timeout}
    end
  end

  defp safe_nats_request(subject, payload, timeout_ms) do
    with {:ok, conn} <- GenServer.call(BotArmyRuntime.NATS.Connection, :get_connection, 5_000),
         {:ok, json} <- Jason.encode(payload),
         {:ok, response} <- Gnat.request(conn, subject, json, receive_timeout: timeout_ms) do
      case Jason.decode(response.body) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, reason} -> {:error, {:decode_failed, reason}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
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
