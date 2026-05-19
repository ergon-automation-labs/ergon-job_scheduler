defmodule BotArmyJobScheduler.ScheduleStore do
  @moduledoc """
  In-memory schedule storage for the Job bot.

  This GenServer maintains the in-memory state of all schedules while Ecto handles
  persistence to PostgreSQL. On init, it loads all schedules from the database.
  Every mutation (create, update, pause, resume) is persisted to the database before updating state.

  ## API

  - `create/1` - Create a new schedule
  - `update/2` - Update an existing schedule
  - `pause/1` - Pause a schedule
  - `resume/1` - Resume a paused schedule
  - `get/1` - Retrieve a schedule by ID
  - `list/0` - List all active schedules
  - `list_all/0` - List all schedules including paused and archived
  """

  use GenServer
  require Logger

  @behaviour BotArmyJobScheduler.ScheduleStoreBehaviour

  @server __MODULE__
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

  # API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @server)
  end

  @doc """
  Create a new schedule from payload.

  Returns `{:ok, schedule}` with the created schedule, or `{:error, reason}`.
  """
  def create(payload) when is_map(payload) do
    GenServer.call(@server, {:create, payload})
  end

  @doc """
  Update an existing schedule.

  Returns `{:ok, schedule}` with the updated schedule, or `{:error, reason}`.
  """
  def update(schedule_id, payload) when is_binary(schedule_id) and is_map(payload) do
    GenServer.call(@server, {:update, schedule_id, payload})
  end

  @doc """
  Pause a schedule.

  Returns `{:ok, schedule}` with the paused schedule, or `{:error, reason}`.
  """
  def pause(schedule_id) when is_binary(schedule_id) do
    GenServer.call(@server, {:pause, schedule_id})
  end

  @doc """
  Resume a paused schedule.

  Returns `{:ok, schedule}` with the resumed schedule, or `{:error, reason}`.
  """
  def resume(schedule_id) when is_binary(schedule_id) do
    GenServer.call(@server, {:resume, schedule_id})
  end

  @doc """
  Retrieve a schedule by ID.

  Returns `{:ok, schedule}` or `{:error, :not_found}`.
  """
  def get(schedule_id) when is_binary(schedule_id) do
    GenServer.call(@server, {:get, schedule_id})
  end

  @doc """
  List all active schedules.

  Returns `{:ok, schedules}`.
  """
  def list do
    GenServer.call(@server, :list)
  end

  @doc """
  List all schedules including paused and archived.

  Returns `{:ok, schedules}`.
  """
  def list_all do
    GenServer.call(@server, :list_all)
  end

  @doc """
  Clear all schedules (for testing).

  Returns `:ok`.
  """
  def clear do
    GenServer.call(@server, :clear)
  end

  # Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ScheduleStore started")
    # Load all schedules from database into GenServer state
    # Gracefully handle database unavailability (e.g., in tests)
    state =
      try do
        schedules = BotArmyJobScheduler.Repo.all(BotArmyJobScheduler.Schemas.Schedule)

        loaded_state =
          Enum.reduce(schedules, %{}, fn schedule, acc ->
            Map.put(acc, schedule.id |> to_string(), schema_to_map(schedule))
          end)

        loaded_state
        |> ensure_schema_sync_schedule()
        |> ensure_para_daily_changed_schedule()
        |> ensure_gtd_para_export_schedule()
        |> ensure_daily_learning_podcast_schedule()
        |> ensure_para_inbox_media_ingest_schedule()
        |> ensure_synapse_scorecard_signals_schedule()
        |> ensure_human_ops_digest_schedule()
        |> ensure_desk_operator_snapshot_schedule()
        |> ensure_bridge_health_snapshot_schedule()
        |> ensure_bridge_chronicle_daily_brief_schedule()
      rescue
        _ ->
          Logger.warning(
            "Could not load schedules from database (database unavailable). Starting with empty state."
          )

          %{}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:create, payload}, _from, state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => payload["title"],
          "description" => Map.get(payload, "description"),
          "cron_expression" => payload["cron_expression"],
          "command" => payload["command"],
          "timeout" => Map.get(payload, "timeout", 3600),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        schedule = schema_to_map(db_schedule)
        new_state = Map.put(state, schedule_id, schedule)
        Logger.info("Created schedule in database: #{schedule_id}")
        {:reply, {:ok, schedule}, new_state}

      {:error, changeset} ->
        Logger.error("Failed to create schedule: #{inspect(changeset.errors)}")
        {:reply, {:error, :database_error}, state}
    end
  end

  @impl true
  def handle_call({:update, schedule_id, payload}, _from, state) do
    case Map.get(state, schedule_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _schedule ->
        schedule_uuid = Ecto.UUID.cast!(schedule_id)

        db_schedule =
          BotArmyJobScheduler.Repo.get(BotArmyJobScheduler.Schemas.Schedule, schedule_uuid)

        if db_schedule do
          changeset =
            BotArmyJobScheduler.Schemas.Schedule.changeset(
              db_schedule,
              %{
                "title" => Map.get(payload, "title", db_schedule.title),
                "description" => Map.get(payload, "description", db_schedule.description),
                "cron_expression" =>
                  Map.get(payload, "cron_expression", db_schedule.cron_expression),
                "command" => Map.get(payload, "command", db_schedule.command),
                "timeout" => Map.get(payload, "timeout", db_schedule.timeout)
              }
            )

          case BotArmyJobScheduler.Repo.update(changeset) do
            {:ok, updated_db_schedule} ->
              updated_schedule = schema_to_map(updated_db_schedule)
              new_state = Map.put(state, schedule_id, updated_schedule)
              Logger.info("Updated schedule in database: #{schedule_id}")
              {:reply, {:ok, updated_schedule}, new_state}

            {:error, changeset} ->
              Logger.error("Failed to update schedule: #{inspect(changeset.errors)}")
              {:reply, {:error, :database_error}, state}
          end
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:pause, schedule_id}, _from, state) do
    case Map.get(state, schedule_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _schedule ->
        schedule_uuid = Ecto.UUID.cast!(schedule_id)

        db_schedule =
          BotArmyJobScheduler.Repo.get(BotArmyJobScheduler.Schemas.Schedule, schedule_uuid)

        if db_schedule do
          changeset =
            BotArmyJobScheduler.Schemas.Schedule.changeset(
              db_schedule,
              %{"status" => "paused"}
            )

          case BotArmyJobScheduler.Repo.update(changeset) do
            {:ok, paused_db_schedule} ->
              paused_schedule = schema_to_map(paused_db_schedule)
              new_state = Map.put(state, schedule_id, paused_schedule)
              Logger.info("Paused schedule in database: #{schedule_id}")
              {:reply, {:ok, paused_schedule}, new_state}

            {:error, changeset} ->
              Logger.error("Failed to pause schedule: #{inspect(changeset.errors)}")
              {:reply, {:error, :database_error}, state}
          end
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:resume, schedule_id}, _from, state) do
    case Map.get(state, schedule_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _schedule ->
        schedule_uuid = Ecto.UUID.cast!(schedule_id)

        db_schedule =
          BotArmyJobScheduler.Repo.get(BotArmyJobScheduler.Schemas.Schedule, schedule_uuid)

        if db_schedule do
          changeset =
            BotArmyJobScheduler.Schemas.Schedule.changeset(
              db_schedule,
              %{"status" => "active"}
            )

          case BotArmyJobScheduler.Repo.update(changeset) do
            {:ok, resumed_db_schedule} ->
              resumed_schedule = schema_to_map(resumed_db_schedule)
              new_state = Map.put(state, schedule_id, resumed_schedule)
              Logger.info("Resumed schedule in database: #{schedule_id}")
              {:reply, {:ok, resumed_schedule}, new_state}

            {:error, changeset} ->
              Logger.error("Failed to resume schedule: #{inspect(changeset.errors)}")
              {:reply, {:error, :database_error}, state}
          end
        else
          {:reply, {:error, :not_found}, state}
        end
    end
  end

  @impl true
  def handle_call({:get, schedule_id}, _from, state) do
    case Map.get(state, schedule_id) do
      nil -> {:reply, {:error, :not_found}, state}
      schedule -> {:reply, {:ok, schedule}, state}
    end
  end

  @impl true
  def handle_call(:list, _from, state) do
    schedules =
      state
      |> Map.values()
      |> Enum.filter(fn s -> s["status"] == "active" end)

    {:reply, {:ok, schedules}, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    schedules = Map.values(state)
    {:reply, {:ok, schedules}, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    Logger.debug("Clearing all schedules")
    {:reply, :ok, %{}}
  end

  # Helper function to convert Ecto schema to map for GenServer state
  defp ensure_schema_sync_schedule(state) do
    if schema_sync_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @schema_sync_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_schema_sync_schedule(state)
      end
    else
      state
    end
  end

  defp schema_sync_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_SCHEMA_SYNC", "true")
    |> String.downcase()
    |> Kernel.!=("false")
  end

  defp create_schema_sync_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Schema Sync Drift Check",
          "description" => "Runs schema-sync and publishes synapse.context.schema_sync.report",
          "cron_expression" => System.get_env("JOB_SCHEDULER_SCHEMA_SYNC_CRON", "*/30 * * * *"),
          "command" => @schema_sync_command,
          "timeout" =>
            String.to_integer(System.get_env("JOB_SCHEDULER_SCHEMA_SYNC_TIMEOUT", "900")),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default schema-sync schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed schema-sync schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_para_daily_changed_schedule(state) do
    if para_daily_changed_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @para_daily_changed_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_para_daily_changed_schedule(state)
      end
    else
      state
    end
  end

  defp para_daily_changed_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_PARA_DAILY_CHANGED", "true")
    |> String.downcase()
    |> Kernel.!=("false")
  end

  defp ensure_gtd_para_export_schedule(state) do
    if gtd_para_export_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @gtd_para_export_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_gtd_para_export_schedule(state)
      end
    else
      state
    end
  end

  defp gtd_para_export_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_GTD_PARA_EXPORT", "true")
    |> String.downcase()
    |> Kernel.!=("false")
  end

  defp create_gtd_para_export_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "GTD PARA Markdown Export",
          "description" => "Runs make gtd-para-export against the Obsidian-backed PARA tree",
          "cron_expression" => System.get_env("JOB_SCHEDULER_GTD_PARA_EXPORT_CRON", "0 * * * *"),
          "command" => @gtd_para_export_command,
          "timeout" =>
            String.to_integer(System.get_env("JOB_SCHEDULER_GTD_PARA_EXPORT_TIMEOUT", "600")),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default GTD PARA export schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed GTD PARA export schedule: #{inspect(reason)}")
        state
    end
  end

  defp create_para_daily_changed_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "PARA Daily What Changed",
          "description" => "Publishes bridge.para.daily.changed.create via monorepo Make target",
          "cron_expression" =>
            System.get_env("JOB_SCHEDULER_PARA_DAILY_CHANGED_CRON", "0 23 * * *"),
          "command" => @para_daily_changed_command,
          "timeout" =>
            String.to_integer(System.get_env("JOB_SCHEDULER_PARA_DAILY_CHANGED_TIMEOUT", "300")),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default PARA daily-changed schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed PARA daily-changed schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_daily_learning_podcast_schedule(state) do
    if daily_learning_podcast_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @daily_learning_podcast_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_daily_learning_podcast_schedule(state)
      end
    else
      state
    end
  end

  defp daily_learning_podcast_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_DAILY_LEARNING_PODCAST", "true")
    |> String.downcase()
    |> Kernel.!=("false")
  end

  defp create_daily_learning_podcast_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Daily Learning Podcast",
          "description" =>
            "Runs make learning-podcast-job from resources/learning/queue.md (resume after dry-run debugging)",
          "cron_expression" =>
            System.get_env("JOB_SCHEDULER_DAILY_LEARNING_PODCAST_CRON", "0 12 * * *"),
          "command" => @daily_learning_podcast_command,
          "timeout" =>
            String.to_integer(
              System.get_env("JOB_SCHEDULER_DAILY_LEARNING_PODCAST_TIMEOUT", "900")
            ),
          "status" => System.get_env("JOB_SCHEDULER_DAILY_LEARNING_PODCAST_STATUS", "paused")
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default daily learning podcast schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed daily learning podcast schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_para_inbox_media_ingest_schedule(state) do
    if para_inbox_media_ingest_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @para_inbox_media_ingest_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_para_inbox_media_ingest_schedule(state)
      end
    else
      state
    end
  end

  defp para_inbox_media_ingest_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_PARA_INBOX_MEDIA_INGEST", "true")
    |> String.downcase()
    |> Kernel.!=("false")
  end

  defp create_para_inbox_media_ingest_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "PARA Inbox YouTube Media Ingest",
          "description" =>
            "Runs make para-inbox-media-ingest-job against inbox/capture.md via bridge + para.fs.write",
          "cron_expression" =>
            System.get_env("JOB_SCHEDULER_PARA_INBOX_MEDIA_INGEST_CRON", "*/30 * * * *"),
          "command" => @para_inbox_media_ingest_command,
          "timeout" =>
            String.to_integer(
              System.get_env("JOB_SCHEDULER_PARA_INBOX_MEDIA_INGEST_TIMEOUT", "900")
            ),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default PARA inbox media ingest schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed PARA inbox media ingest schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_synapse_scorecard_signals_schedule(state) do
    if synapse_scorecard_signals_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @synapse_scorecard_signals_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_synapse_scorecard_signals_schedule(state)
      end
    else
      state
    end
  end

  defp synapse_scorecard_signals_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_SYNAPSE_SCORECARD_SIGNALS", "false")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes"])
  end

  defp create_synapse_scorecard_signals_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Synapse scorecard signals + PARA",
          "description" =>
            "Runs make synapse-scorecard-signals-with-para (LLM + agentic NATS + para.fs.write copies)",
          "cron_expression" =>
            System.get_env(
              "JOB_SCHEDULER_SYNAPSE_SCORECARD_SIGNALS_CRON",
              "30 13 * * *"
            ),
          "command" => @synapse_scorecard_signals_command,
          "timeout" =>
            String.to_integer(
              System.get_env("JOB_SCHEDULER_SYNAPSE_SCORECARD_SIGNALS_TIMEOUT", "3600")
            ),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default Synapse scorecard + PARA schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed Synapse scorecard signals schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_human_ops_digest_schedule(state) do
    if human_ops_digest_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @human_ops_digest_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_human_ops_digest_schedule(state)
      end
    else
      state
    end
  end

  defp human_ops_digest_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_HUMAN_OPS_DIGEST", "false")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes"])
  end

  defp create_human_ops_digest_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Human ops digest (PARA + Discord)",
          "description" =>
            "Runs make human-ops-digest-job (PARA sync + weekly GTD + orchestration + risk-health → PARA + Discord + Synapse)",
          "cron_expression" =>
            System.get_env(
              "JOB_SCHEDULER_HUMAN_OPS_DIGEST_CRON",
              "0 14 * * 1"
            ),
          "command" => @human_ops_digest_command,
          "timeout" =>
            String.to_integer(System.get_env("JOB_SCHEDULER_HUMAN_OPS_DIGEST_TIMEOUT", "3600")),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default human ops digest schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed human ops digest schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_desk_operator_snapshot_schedule(state) do
    if desk_operator_snapshot_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @desk_operator_snapshot_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_desk_operator_snapshot_schedule(state)
      end
    else
      state
    end
  end

  defp desk_operator_snapshot_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_DESK_OPERATOR_SNAPSHOT", "false")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes"])
  end

  defp create_desk_operator_snapshot_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Desk Operator Snapshot",
          "description" =>
            "NATS request to bot.army.skills.desk_operator_snapshot.generate — deterministic desk assembly for operator reports",
          "cron_expression" =>
            System.get_env(
              "JOB_SCHEDULER_DESK_OPERATOR_SNAPSHOT_CRON",
              "0 8 * * *"
            ),
          "command" => @desk_operator_snapshot_command,
          "timeout" =>
            String.to_integer(
              System.get_env("JOB_SCHEDULER_DESK_OPERATOR_SNAPSHOT_TIMEOUT", "60")
            ),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default desk operator snapshot schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed desk operator snapshot schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_bridge_health_snapshot_schedule(state) do
    if bridge_health_snapshot_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @bridge_health_snapshot_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_bridge_health_snapshot_schedule(state)
      end
    else
      state
    end
  end

  defp bridge_health_snapshot_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_BRIDGE_HEALTH_SNAPSHOT", "false")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes"])
  end

  defp create_bridge_health_snapshot_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Bridge Health Snapshot",
          "description" =>
            "NATS request to bot.army.skills.bridge_health_snapshot.generate — health snapshot written to PARA",
          "cron_expression" =>
            System.get_env(
              "JOB_SCHEDULER_BRIDGE_HEALTH_SNAPSHOT_CRON",
              "*/30 * * * *"
            ),
          "command" => @bridge_health_snapshot_command,
          "timeout" =>
            String.to_integer(
              System.get_env("JOB_SCHEDULER_BRIDGE_HEALTH_SNAPSHOT_TIMEOUT", "60")
            ),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default bridge health snapshot schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed bridge health snapshot schedule: #{inspect(reason)}")
        state
    end
  end

  defp ensure_bridge_chronicle_daily_brief_schedule(state) do
    if bridge_chronicle_daily_brief_enabled?() do
      has_schedule? =
        state
        |> Map.values()
        |> Enum.any?(fn schedule ->
          schedule["command"] == @bridge_chronicle_daily_brief_command and
            schedule["status"] in ["active", "paused"]
        end)

      if has_schedule? do
        state
      else
        create_bridge_chronicle_daily_brief_schedule(state)
      end
    else
      state
    end
  end

  defp bridge_chronicle_daily_brief_enabled? do
    System.get_env("JOB_SCHEDULER_ENABLE_BRIDGE_CHRONICLE_DAILY_BRIEF", "false")
    |> String.downcase()
    |> Kernel.in(["1", "true", "yes"])
  end

  defp create_bridge_chronicle_daily_brief_schedule(state) do
    schedule_id = Ecto.UUID.generate()

    changeset =
      BotArmyJobScheduler.Schemas.Schedule.changeset(
        %BotArmyJobScheduler.Schemas.Schedule{id: schedule_id},
        %{
          "title" => "Bridge Chronicle Daily Brief",
          "description" =>
            "Runs make bridge-chronicle-daily-brief-write — writes daily brief to para-bot/inbox/daily-brief.md",
          "cron_expression" =>
            System.get_env(
              "JOB_SCHEDULER_BRIDGE_CHRONICLE_DAILY_BRIEF_CRON",
              "0 7 * * *"
            ),
          "command" => @bridge_chronicle_daily_brief_command,
          "timeout" =>
            String.to_integer(
              System.get_env("JOB_SCHEDULER_BRIDGE_CHRONICLE_DAILY_BRIEF_TIMEOUT", "120")
            ),
          "status" => "active"
        }
      )

    case BotArmyJobScheduler.Repo.insert(changeset) do
      {:ok, db_schedule} ->
        Logger.info("Seeded default bridge chronicle daily brief schedule: #{schedule_id}")
        Map.put(state, schedule_id, schema_to_map(db_schedule))

      {:error, reason} ->
        Logger.error("Failed to seed bridge chronicle daily brief schedule: #{inspect(reason)}")
        state
    end
  end

  defp schema_to_map(%BotArmyJobScheduler.Schemas.Schedule{} = schedule) do
    %{
      "id" => Ecto.UUID.cast!(schedule.id) |> to_string(),
      "title" => schedule.title,
      "description" => schedule.description,
      "cron_expression" => schedule.cron_expression,
      "command" => schedule.command,
      "timeout" => schedule.timeout,
      "status" => schedule.status,
      "last_run_at" =>
        if(schedule.last_run_at,
          do: schedule.last_run_at |> NaiveDateTime.to_iso8601(),
          else: nil
        ),
      "created_at" => schedule.inserted_at |> NaiveDateTime.to_iso8601(),
      "updated_at" => schedule.updated_at |> NaiveDateTime.to_iso8601()
    }
  end
end
