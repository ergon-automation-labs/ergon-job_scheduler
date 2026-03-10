defmodule BotArmyJob.ScheduleStoreBehaviour do
  @moduledoc """
  Behaviour definition for schedule storage.

  Allows different implementations (real database, mock) to be swapped via configuration.
  """

  @doc """
  Create a new schedule from payload.

  Returns `{:ok, schedule}` with the created schedule, or `{:error, reason}`.
  """
  @callback create(payload :: map()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Update an existing schedule.

  Returns `{:ok, schedule}` with the updated schedule, or `{:error, reason}`.
  """
  @callback update(schedule_id :: String.t(), payload :: map()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Pause a schedule.

  Returns `{:ok, schedule}` with the paused schedule, or `{:error, reason}`.
  """
  @callback pause(schedule_id :: String.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Resume a paused schedule.

  Returns `{:ok, schedule}` with the resumed schedule, or `{:error, reason}`.
  """
  @callback resume(schedule_id :: String.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  Retrieve a schedule by ID.

  Returns `{:ok, schedule}` or `{:error, :not_found}`.
  """
  @callback get(schedule_id :: String.t()) :: {:ok, map()} | {:error, atom()}

  @doc """
  List all active schedules.

  Returns `{:ok, schedules}`.
  """
  @callback list() :: {:ok, list(map())}

  @doc """
  List all schedules including paused and archived.

  Returns `{:ok, schedules}`.
  """
  @callback list_all() :: {:ok, list(map())}

  @doc """
  Clear all schedules (for testing).

  Returns `:ok`.
  """
  @callback clear() :: :ok
end
