defmodule BotArmyJobScheduler.BoundedCommandTest do
  use ExUnit.Case, async: true

  @moduletag :core

  alias BotArmyJobScheduler.BoundedCommand

  # Regression context (2026-09-22): the scheduler bounded commands with
  # `Process.exit(pid, :kill)` on the BEAM process that owned the port. That left
  # the OS process tree (`make -> /bin/sh -c -> python3`) alive and unreaped under
  # `erl_child_setup`. Runs accumulated for 11 days: 507 stacked job processes,
  # load average 724, ~90 MB free RAM, and every air deploy failing with "Minion
  # did not return". The tests below pin the invariant that was missing: after a
  # timeout, nothing the call spawned is still running.
  #
  # Unique sleep durations per test keep the process assertions independent of any
  # other `sleep` on the machine.

  defp live_survivors(marker) do
    {output, _} = System.cmd("/bin/ps", ["-axo", "command="], stderr_to_stdout: true)

    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.contains?(&1, marker))
    |> Enum.reject(&String.contains?(&1, "defunct"))
    |> Enum.reject(&String.contains?(&1, "ps -axo command="))
  end

  defp eventually_no_survivors(marker, budget_ms \\ 3_000) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    do_await_survivors(marker, deadline)
  end

  defp do_await_survivors(marker, deadline) do
    case live_survivors(marker) do
      [] ->
        :ok

      survivors ->
        if System.monotonic_time(:millisecond) >= deadline do
          flunk("processes survived the deadline: #{inspect(survivors)}")
        else
          Process.sleep(100)
          do_await_survivors(marker, deadline)
        end
    end
  end

  test "captures stdout and a zero exit status" do
    assert {output, 0} = BoundedCommand.run("/bin/echo", ["hello"], timeout_ms: 5_000)
    assert String.trim(output) == "hello"
  end

  test "merges stderr into the captured output" do
    assert {output, 0} =
             BoundedCommand.run("/bin/bash", ["-c", "echo out; echo err >&2"], timeout_ms: 5_000)

    assert output =~ "out"
    assert output =~ "err"
  end

  test "reports a non-zero exit status" do
    assert {_output, 3} = BoundedCommand.run("/bin/bash", ["-c", "exit 3"], timeout_ms: 5_000)
  end

  test "fails fast when the executable does not exist" do
    assert_raise ErlangError, fn ->
      BoundedCommand.run("/nonexistent/definitely-not-here", [], timeout_ms: 1_000)
    end
  end

  test "a deadline terminates the whole process tree, not just the port owner" do
    # Three levels deep, mirroring the production chain make -> sh -> python3.
    # `sleep 987` at the bottom is the process that used to survive forever.
    command = ~s(bash -c "sleep 987" & sleep 987)

    assert {_output, :timeout} =
             BoundedCommand.run("/bin/bash", ["-c", command], timeout_ms: 400)

    assert :ok = eventually_no_survivors("sleep 987")
  end

  test "the deadline is hard even while the child keeps producing output" do
    # A chatty child used to be able to reset a naive `receive ... after` budget.
    started = System.monotonic_time(:millisecond)

    assert {_output, :timeout} =
             BoundedCommand.run(
               "/bin/bash",
               ["-c", "while true; do echo tick; sleep 0.05; done"],
               timeout_ms: 500
             )

    elapsed = System.monotonic_time(:millisecond) - started
    assert elapsed < 5_000, "chatty child outlived its deadline (#{elapsed}ms)"
  end

  test "descendants/1 includes leaves and puts the root last" do
    port =
      Port.open({:spawn_executable, "/bin/bash"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-c", "sleep 986 & sleep 986"]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    # bash forks its children asynchronously: reading the table immediately can
    # legitimately observe the root alone. In production the tree has been running
    # for the whole deadline, so polling here mirrors reality instead of racing it.
    tree = await_tree(os_pid, 3_000)

    assert List.last(tree) == os_pid
    assert length(tree) >= 3, "expected bash + two sleeps, got #{inspect(tree)}"
    assert BoundedCommand.alive?(os_pid)

    Enum.each(tree, &System.cmd("/bin/kill", ["-KILL", Integer.to_string(&1)]))
    Port.close(port)
  rescue
    # The port is already closed once the killed root exits; that is fine here.
    ArgumentError -> :ok
  end

  defp await_tree(os_pid, budget_ms) do
    deadline = System.monotonic_time(:millisecond) + budget_ms
    do_await_tree(os_pid, deadline)
  end

  defp do_await_tree(os_pid, deadline) do
    tree = BoundedCommand.descendants(os_pid)

    if length(tree) >= 3 or System.monotonic_time(:millisecond) >= deadline do
      tree
    else
      Process.sleep(50)
      do_await_tree(os_pid, deadline)
    end
  end
end
