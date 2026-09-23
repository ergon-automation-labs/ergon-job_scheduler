defmodule BotArmyJobScheduler.StaleJobTreeTest do
  use ExUnit.Case, async: false

  @moduletag :core
  @tag :integration
  @moduletag :integration

  alias BotArmyJobScheduler.BoundedCommand

  # Full-path end-to-end regression for the 2026-09-22 runaway.
  #
  # This runs the SAME command shape the fleet scheduler runs for the PARA export
  # — `make gtd-para-export PARA_SYNC_ROOT=… PARA_SYNC_BOT_DROP=… PORT=…` against
  # the live PARA root — with a short deadline, and then asserts the machine is
  # clean. Before the fix, this left `make` + `/bin/sh -c …` + `python3
  # gtd_para_export.py` running forever (507 of them accumulated over 11 days),
  # because only the BEAM process owning the port was killed.
  #
  # PORT is pinned to the hermetic test port so a probe can never publish to the
  # live production broker. The path may or may not still be wedged, so the exit
  # status is not asserted — the assertion is the invariant: nothing survives.
  @marker "gtd_para_export.py"
  @hermetic_port 42_991

  test "the real PARA export command shape leaves no process behind" do
    elixir_bots_dir = System.get_env("ELIXIR_BOTS_DIR", "/Users/abby/code/elixir_bots")
    para_root = System.get_env("PARA_SYNC_ROOT", "/Users/abby/Documents/personal_os")
    make = System.find_executable("make")

    assert make, "make must be on PATH for this integration test"

    before = job_processes()

    args = [
      "gtd-para-export",
      "PARA_SYNC_ROOT=#{para_root}",
      "PARA_SYNC_BOT_DROP=para-bot/inbox",
      "PORT=#{@hermetic_port}"
    ]

    {_output, status} =
      BoundedCommand.run(make, args, cd: elixir_bots_dir, timeout_ms: 10_000)

    assert status in [:timeout, 0, 1, 2],
           "unexpected status from the bounded run: #{inspect(status)}"

    # SIGKILL is immediate but reaping is asynchronous; give it a moment, then hold
    # the line: the count must not have grown.
    Process.sleep(1_000)
    after_count = job_processes()

    assert after_count <= before,
           "job processes leaked: #{before} before, #{after_count} after"
  end

  defp job_processes do
    {output, _} = System.cmd("/bin/ps", ["-axo", "command="], stderr_to_stdout: true)

    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.contains?(&1, @marker))
    |> Enum.reject(&String.contains?(&1, "defunct"))
    |> length()
  end
end
