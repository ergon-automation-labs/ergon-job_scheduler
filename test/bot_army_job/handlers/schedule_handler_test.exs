defmodule BotArmyJobScheduler.Handlers.ScheduleHandlerTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  describe "handle_create/1" do
    test "successfully creates a schedule" do
      payload = %{
        "job_name" => "backup_job",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "description" => "Backup all user data"
      }

      expected_schedule = %{
        "id" => "test-id",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "description" => "Backup all user data",
        "status" => "active",
        "timeout" => 3600,
        "created_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :create, fn ^payload ->
        {:ok, expected_schedule}
      end)

      message = valid_create_message()
      assert :ok = BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
    end

    test "returns error for missing required fields" do
      message =
        valid_create_message()
        |> put_in(["payload", "job_name"], nil)

      assert :ok = BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
    end

    test "requires both job_name and cron_expression" do
      message =
        valid_create_message()
        |> put_in(["payload", "cron_expression"], nil)

      assert :ok = BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
    end

    test "sets correct default values" do
      payload = %{
        "job_name" => "backup_job",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "description" => "Backup all user data"
      }

      expected_schedule = %{
        "id" => "test-id",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "status" => "active",
        "timeout" => 3600,
        "created_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :create, fn ^payload ->
        {:ok, expected_schedule}
      end)

      message = valid_create_message()
      BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
    end

    test "includes job_name and cron_expression in created schedule" do
      payload = %{
        "job_name" => "backup_job",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "description" => "Backup all user data"
      }

      expected_schedule = %{
        "id" => "test-id",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "description" => "Backup all user data",
        "status" => "active",
        "timeout" => 3600,
        "created_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :create, fn ^payload ->
        {:ok, expected_schedule}
      end)

      message = valid_create_message()
      BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
    end

    test "accepts optional command, timeout, and description" do
      payload = %{
        "job_name" => "backup_job",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "timeout" => 3600,
        "description" => "Backup all user data"
      }

      expected_schedule = %{
        "id" => "test-id",
        "title" => "Daily Backup",
        "cron_expression" => "0 0 * * *",
        "command" => "/scripts/backup.sh",
        "timeout" => 3600,
        "status" => "active",
        "created_at" => "2024-01-01T00:00:00",
        "updated_at" => "2024-01-01T00:00:00"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :create, fn ^payload ->
        {:ok, expected_schedule}
      end)

      message =
        valid_create_message()
        |> put_in(["payload", "command"], "/scripts/backup.sh")
        |> put_in(["payload", "timeout"], 3600)

      BotArmyJobScheduler.Handlers.ScheduleHandler.handle_create(message)
    end
  end

  describe "handle_update/1" do
    test "successfully updates an existing schedule" do
      schedule_id = "test-schedule-id"

      payload = %{
        "schedule_id" => schedule_id,
        "title" => "Hourly Backup",
        "cron_expression" => "0 * * * *"
      }

      expected_schedule = %{
        "id" => schedule_id,
        "title" => "Hourly Backup",
        "cron_expression" => "0 * * * *",
        "status" => "active"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :update, fn ^schedule_id, ^payload ->
        {:ok, expected_schedule}
      end)

      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => payload
      }

      BotArmyJobScheduler.Handlers.ScheduleHandler.handle_update(update_msg)
    end

    test "returns error when updating non-existent schedule" do
      schedule_id = "non-existent-id"

      payload = %{
        "schedule_id" => schedule_id,
        "title" => "Updated Title"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :update, fn ^schedule_id, ^payload ->
        {:error, :not_found}
      end)

      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => payload
      }

      assert :ok = BotArmyJobScheduler.Handlers.ScheduleHandler.handle_update(update_msg)
    end

    test "preserves unmodified fields during update" do
      schedule_id = "test-schedule-id"

      payload = %{
        "schedule_id" => schedule_id,
        "title" => "New Title"
      }

      expected_schedule = %{
        "id" => schedule_id,
        "title" => "New Title",
        "cron_expression" => "0 0 * * *",
        "status" => "active"
      }

      Mox.expect(BotArmyJobScheduler.ScheduleStoreMock, :update, fn ^schedule_id, ^payload ->
        {:ok, expected_schedule}
      end)

      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => payload
      }

      BotArmyJobScheduler.Handlers.ScheduleHandler.handle_update(update_msg)
    end

    test "requires schedule_id for update" do
      update_msg = %{
        "event_id" => UUID.uuid4(),
        "event" => "job.schedule.update",
        "payload" => %{
          "title" => "Updated Title"
        }
      }

      assert :ok = BotArmyJobScheduler.Handlers.ScheduleHandler.handle_update(update_msg)
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
