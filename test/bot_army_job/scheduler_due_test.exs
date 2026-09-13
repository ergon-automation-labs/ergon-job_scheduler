defmodule BotArmyJobScheduler.SchedulerDueTest do
  use ExUnit.Case, async: true

  alias BotArmyJobScheduler.Scheduler

  @six_hours 6 * 60 * 60

  # Regression context (2026-09-12/13): due evaluation used an exact-minute
  # match against `now` and cached last_run_at values were emitted without a
  # UTC offset (unparseable), so the Companion schedules silently skipped every
  # slot once the check loop started drifting (blocking jobs / machine sleep).

  defp schedule(last_run_at) do
    %{
      "id" => "c7c8d3e9-a1b2-45c3-90d2-f1a2b3c4d5e6",
      "title" => "Reflection Due Test",
      "status" => "active",
      "cron_expression" => "0 */6 * * *",
      "command" => "companion.reflection",
      "last_run_at" => last_run_at
    }
  end

  defp now_at(iso) do
    {:ok, dt, _offset} = DateTime.from_iso8601(iso)
    dt
  end

  test "fires a missed boundary on the next check (catch-up within grace)" do
    # Boundary 06:00 UTC; check drifts to 09:47; last run the previous morning.
    now = now_at("2026-09-13T09:47:07Z")
    assert Scheduler.schedule_due?(schedule("2026-09-12T08:47:00Z"), now)
  end

  test "parses offset-less binary last_run_at (schema_to_map format)" do
    now = now_at("2026-09-13T09:47:07Z")
    # Without the naive fallback this degraded to the never-run sentinel and
    # not_recently_run was vacuously true.
    assert Scheduler.schedule_due?(schedule("2026-09-13T06:00:00"), now) == false
    assert Scheduler.schedule_due?(schedule("2026-09-12T20:00:00"), now)
  end

  test "does not re-fire a boundary that was already run" do
    now = now_at("2026-09-13T09:47:07Z")
    # Ran at 06:05, five minutes after the 06:00 boundary.
    refute Scheduler.schedule_due?(schedule("2026-09-13T06:05:00Z"), now)
  end

  test "fires during the exact cron minute" do
    now = now_at("2026-09-13T06:00:30Z")
    assert Scheduler.schedule_due?(schedule("2026-09-13T05:00:00Z"), now)
  end

  test "never-run schedule fires when a boundary is within grace" do
    now = now_at("2026-09-13T09:47:07Z")
    assert Scheduler.schedule_due?(schedule(nil), now)
  end

  test "stale boundary beyond the grace window is skipped" do
    now = now_at("2026-09-13T09:47:07Z")

    stale = %{
      schedule(nil)
      | "cron_expression" => "0 3 * * *",
        "id" => "11111111-2222-4333-8444-555555555555"
    }

    # 03:00 UTC boundary is 6h47m old — beyond @six_hours.
    assert @six_hours < DateTime.diff(now, now_at("2026-09-13T03:00:00Z"))
    refute Scheduler.schedule_due?(stale, now)
  end

  test "paused schedules never fire" do
    now = now_at("2026-09-13T09:47:07Z")
    paused = %{schedule(nil) | "status" => "paused"}
    refute Scheduler.schedule_due?(paused, now)
  end

  test "invalid cron expression never fires" do
    now = now_at("2026-09-13T09:47:07Z")
    bad = %{schedule(nil) | "cron_expression" => "not a cron"}
    refute Scheduler.schedule_due?(bad, now)
  end
end
