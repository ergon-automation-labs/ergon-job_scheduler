defmodule BotArmyJobScheduler.BoundedCommand do
  @moduledoc """
  Run an OS command under a deadline that actually ends the process tree.

  ## Why this module exists (2026-09-22 incident)

  The scheduler used `System.cmd/3` inside an unlinked spawn, bounded with a
  `receive ... after timeout_ms -> Process.exit(pid, :kill)` pattern. That kills
  the BEAM process that owns the port, but **not the OS process tree**. A job of
  the shape `make … -> /bin/sh -c … -> python3 …` therefore lost only its `make`
  head at best; the remaining processes were orphaned while the port stayed open
  under `erl_child_setup`, kept running forever, and the scheduler — believing the
  run had ended — started a fresh copy at the next tick.

  Measured result: 11 days of accumulation, 507 stacked job processes, load
  average 724, ~90 MB free RAM, and a salt minion starved into "Minion did not
  return" on every deploy. Runbook:
  `docs/runbooks/KNOWN_ISSUE_JOB_SCHEDULER_RUNAWAY_AND_MINION_WEDGE.md`.

  The invariant this module guarantees is the one that was missing:

      when `run/3` returns `{_, :timeout}`, no process spawned by that call is
      still alive.

  ## How the tree is ended

  1. `Port.open({:spawn_executable, path}, …)` — the port reports `:os_pid`.
  2. On deadline, walk `ps -axo pid=,ppid=` to collect the descendants of that
     `os_pid`, deepest first, and `SIGTERM` them (children before the head, so
     `make` cannot fork more work while it dies).
  3. Wait `@term_grace_ms` for a clean exit; `SIGKILL` whatever is still alive.
  4. Close the port and drain its messages so the caller's mailbox stays clean.

  ## Caveat

  If the BEAM itself dies mid-run (a deploy restart), the port closes and the OS
  children are orphaned like any other daemon child. That residual is bounded —
  at most one instance per schedule per restart — and `make node-storm-clear`
  sweeps any leftovers.
  """

  require Logger

  @default_timeout_ms 30_000
  @term_grace_ms 2_000
  @poll_ms 50
  @drain_ms 250

  @type result :: {binary(), non_neg_integer() | :timeout}

  @doc """
  Run `executable` with `args`, returning `{output, exit_status}`.

  `output` is stdout+stderr merged. On deadline expiry the tree is terminated and
  the exit status is the atom `:timeout`.

  ## Options

    * `:timeout_ms` — deadline in milliseconds (default #{@default_timeout_ms})
    * `:cd` — working directory
    * `:env` — list of `{name, value}` OS environment overrides (additive: the
      behaviour matches `System.cmd/3`'s `:env`, which *replaces* if given, so
      callers should pass the full environment only when that is intended)
  """
  @spec run(String.t(), [String.t()], keyword()) :: result()
  def run(executable, args, opts \\ []) when is_binary(executable) and is_list(args) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    port = open_port(executable, args, opts)
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    collect(port, [], deadline)
  end

  @doc """
  Pids belonging to the process tree rooted at `os_pid`, deepest first.

  The root is always last so callers can signal children before the head. A
  leaf (e.g. the `python3` at the bottom of `make -> sh -> python3`) is still a
  member — omitting leaves was the original bug this module replaces.
  """
  @spec descendants(integer()) :: [integer()]
  def descendants(os_pid) when is_integer(os_pid) do
    # postorder/4 accumulates by prepending, so reverse once here.
    os_pid
    |> postorder(children_table(), MapSet.new(), [])
    |> Enum.reverse()
  end

  @doc "True when `os_pid` still exists."
  @spec alive?(integer()) :: boolean()
  def alive?(os_pid) when is_integer(os_pid) do
    case System.cmd("/bin/ps", ["-o", "pid=", "-p", Integer.to_string(os_pid)],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp open_port(executable, args, opts) do
    port_opts =
      [:binary, :exit_status, :stderr_to_stdout, {:args, args}]
      |> maybe_put(:cd, Keyword.get(opts, :cd))
      |> maybe_put_env(Keyword.get(opts, :env))

    Port.open({:spawn_executable, executable}, port_opts)
  end

  defp maybe_put(port_opts, _key, nil), do: port_opts
  defp maybe_put(port_opts, key, value), do: [{key, value} | port_opts]

  defp maybe_put_env(port_opts, nil), do: port_opts
  defp maybe_put_env(port_opts, env), do: [{:env, env} | port_opts]

  # Hard deadline: recompute the remaining budget on every message, otherwise a
  # chatty child keeps resetting the `after` clause and runs forever.
  defp collect(port, acc, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      on_timeout(port, acc)
    else
      receive do
        {^port, {:data, data}} -> collect(port, [data | acc], deadline)
        {^port, {:exit_status, status}} -> {join(acc), status}
      after
        remaining -> on_timeout(port, acc)
      end
    end
  end

  defp on_timeout(port, acc) do
    {drained, _} = terminate_tree(port)
    Logger.error("[BoundedCommand] killed process tree after deadline")
    {join(acc ++ [drained]), :timeout}
  end

  # Returns {output_drained_while_killing, :exited | :killed}.
  defp terminate_tree(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> kill_tree(port, os_pid)
      nil -> {drain(port, [], @drain_ms), :exited}
    end
  end

  defp kill_tree(port, os_pid) do
    tree = descendants(os_pid)
    signal(tree, "TERM")
    {output, exited?} = await_death(port, [], @term_grace_ms)

    if exited? do
      close(port)
      {output, :exited}
    else
      signal(tree, "KILL")
      output = output <> drain(port, [], @drain_ms)
      close(port)
      {output, :killed}
    end
  end

  defp await_death(port, acc, budget_ms) do
    if budget_ms <= 0 do
      {join(acc), false}
    else
      receive do
        {^port, {:data, data}} -> await_death(port, [data | acc], budget_ms)
        {^port, {:exit_status, _status}} -> {join(acc), true}
      after
        @poll_ms -> await_death(port, acc, budget_ms - @poll_ms)
      end
    end
  end

  defp drain(port, acc, budget_ms) do
    if budget_ms <= 0 do
      join(acc)
    else
      receive do
        {^port, {:data, data}} -> drain(port, [data | acc], budget_ms)
        {^port, {:exit_status, _status}} -> drain(port, acc, 0)
      after
        @poll_ms -> drain(port, acc, budget_ms - @poll_ms)
      end
    end
  end

  defp close(port) do
    Port.close(port)
  rescue
    _ -> :ok
  end

  defp signal(pids, signal) do
    Enum.each(pids, fn pid ->
      System.cmd("/bin/kill", ["-#{signal}", Integer.to_string(pid)], stderr_to_stdout: true)
    end)
  end

  defp children_table do
    case System.cmd("/bin/ps", ["-axo", "pid=,ppid="], stderr_to_stdout: true) do
      {output, 0} -> output |> parse_ps() |> group_by_parent()
      _ -> %{}
    end
  rescue
    _ -> %{}
  end

  defp parse_ps(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.split(String.trim(line), ~r/\s+/) do
        [pid, ppid] ->
          case {Integer.parse(pid), Integer.parse(ppid)} do
            {{pid_int, _}, {ppid_int, _}} -> [{pid_int, ppid_int}]
            _ -> []
          end

        _ ->
          []
      end
    end)
  end

  defp group_by_parent(pairs) do
    Enum.reduce(pairs, %{}, fn {pid, ppid}, acc ->
      Map.update(acc, ppid, [pid], &[pid | &1])
    end)
  end

  # Children before self, so `make` is signalled after the processes it forked.
  # `seen` guards against a pid-reuse cycle turning this into infinite recursion.
  defp postorder(pid, table, seen, acc) do
    if MapSet.member?(seen, pid) do
      acc
    else
      seen = MapSet.put(seen, pid)

      acc =
        table
        |> Map.get(pid, [])
        |> Enum.reduce(acc, fn child, inner -> postorder(child, table, seen, inner) end)

      [pid | acc]
    end
  end

  defp join(chunks) do
    chunks |> Enum.reverse() |> IO.iodata_to_binary()
  end
end
