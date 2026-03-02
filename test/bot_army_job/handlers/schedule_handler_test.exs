defmodule BotArmyJob.Handlers.ScheduleHandlerTest do
  use ExUnit.Case

  setup do
    # Clear the schedule store before each test
    case BotArmyJob.ScheduleStore.start_link([]) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Clear all schedules
    BotArmyJob.ScheduleStore.clear()
    :ok
  end

  describe "handle_create/1" do
    test "successfully creates a schedule" do
      message = valid_create_message()

      assert :ok = BotArmyJob.Handlers.ScheduleHandler.handle_create(message)

      # Verify the schedule was stored
      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      assert length(schedules) > 0

      schedule = List.first(schedules)
      assert schedule["title"] == "Daily Backup"
      assert schedule["cron_expression"] == "0 0 * * *"
    end

    test "returns error for missing required fields" do
      message =
        valid_create_message()
        |> put_in(["payload", "job_name"], nil)

      assert :ok = BotArmyJob.Handlers.ScheduleHandler.handle_create(message)

      # Schedule should not be created
      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      assert length(schedules) == 0
    end

    test "requires both job_name and cron_expression" do
      message =
        valid_create_message()
        |> put_in(["payload", "cron_expression"], nil)

      assert :ok = BotArmyJob.Handlers.ScheduleHandler.handle_create(message)

      # Schedule should not be created
      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      assert length(schedules) == 0
    end

    test "sets correct default values" do
      message = valid_create_message()

      BotArmyJob.Handlers.ScheduleHandler.handle_create(message)

      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      schedule = List.first(schedules)

      assert schedule["status"] == "active"
      assert is_binary(schedule["id"])
    end

    test "includes job_name and cron_expression in created schedule" do
      message = valid_create_message()

      BotArmyJob.Handlers.ScheduleHandler.handle_create(message)

      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      schedule = List.first(schedules)

      assert schedule["title"] == "Daily Backup"
      assert schedule["cron_expression"] == "0 0 * * *"
      assert schedule["description"] == "Backup all user data"
    end

    test "accepts optional command, timeout, and description" do
      message =
        valid_create_message()
        |> put_in(["payload", "command"], "/scripts/backup.sh")
        |> put_in(["payload", "timeout"], 3600)

      BotArmyJob.Handlers.ScheduleHandler.handle_create(message)

      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      schedule = List.first(schedules)

      assert schedule["command"] == "/scripts/backup.sh"
      assert schedule["timeout"] == 3600
    end
  end

  describe "handle_update/1" do
    test "successfully updates an existing schedule" do
      # Create a schedule first
      create_msg = valid_create_message()
      BotArmyJob.Handlers.ScheduleHandler.handle_create(create_msg)

      # Get the created schedule
      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      schedule = List.first(schedules)
      schedule_id = schedule["id"]

      # Update the schedule
      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => %{
          "schedule_id" => schedule_id,
          "title" => "Hourly Backup",
          "cron_expression" => "0 * * * *"
        }
      }

      BotArmyJob.Handlers.ScheduleHandler.handle_update(update_msg)

      # Verify the schedule was updated
      {:ok, updated_schedule} = BotArmyJob.ScheduleStore.get(schedule_id)
      assert updated_schedule["title"] == "Hourly Backup"
      assert updated_schedule["cron_expression"] == "0 * * * *"
    end

    test "returns error when updating non-existent schedule" do
      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => %{
          "schedule_id" => "non-existent-id",
          "title" => "Updated Title"
        }
      }

      assert :ok = BotArmyJob.Handlers.ScheduleHandler.handle_update(update_msg)

      # Verify no schedules were created
      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      assert length(schedules) == 0
    end

    test "preserves unmodified fields during update" do
      # Create a schedule
      create_msg = valid_create_message()
      BotArmyJob.Handlers.ScheduleHandler.handle_create(create_msg)

      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      schedule = List.first(schedules)
      schedule_id = schedule["id"]
      original_cron = schedule["cron_expression"]

      # Update only the title
      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => %{
          "schedule_id" => schedule_id,
          "title" => "New Title"
        }
      }

      BotArmyJob.Handlers.ScheduleHandler.handle_update(update_msg)

      # Verify cron expression was preserved
      {:ok, updated_schedule} = BotArmyJob.ScheduleStore.get(schedule_id)
      assert updated_schedule["title"] == "New Title"
      assert updated_schedule["cron_expression"] == original_cron
    end

    test "requires schedule_id for update" do
      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => %{
          "title" => "Updated Title"
        }
      }

      assert :ok = BotArmyJob.Handlers.ScheduleHandler.handle_update(update_msg)

      # Verify no schedules were affected
      {:ok, schedules} = BotArmyJob.ScheduleStore.list()
      assert length(schedules) == 0
    end
  end

  # Helper functions

  defp valid_create_message do
    %{
      "event_id" => UUID.uuid4(),
      "event" => "job.schedule.create",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "test_client",
      "source_node" => "test_node",
      "triggered_by" => "manual",
      "schema_version" => "1.0",
      "payload" => %{
        "job_name" => "backup_job",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "description" => "Backup all user data"
      }
    }
  end
end
