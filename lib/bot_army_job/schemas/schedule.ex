defmodule BotArmyJobScheduler.Schemas.Schedule do
  @moduledoc """
  Ecto schema for job schedules.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, Ecto.UUID, autogenerate: true}

  schema "schedules" do
    field :title, :string
    field :description, :string
    field :cron_expression, :string
    field :command, :string
    field :timeout, :integer, default: 3600
    field :status, :string, default: "active"
    field :last_run_at, :naive_datetime

    timestamps()
  end

  @doc false
  def changeset(schedule, attrs) do
    schedule
    |> cast(attrs, [:title, :description, :cron_expression, :command, :timeout, :status, :last_run_at])
    |> validate_required([:title, :cron_expression, :command])
    |> validate_inclusion(:status, ["active", "paused", "archived"])
    |> validate_number(:timeout, greater_than: 0)
    |> validate_cron_expression(:cron_expression)
  end

  def changeset_from_payload(schedule, payload) do
    schedule
    |> cast(payload, [:title, :description, :cron_expression, :command, :timeout, :status, :last_run_at])
    |> validate_required([:cron_expression, :command])
    |> validate_inclusion(:status, ["active", "paused", "archived"])
    |> validate_number(:timeout, greater_than: 0)
    |> validate_cron_expression(:cron_expression)
  end

  # Basic cron expression validation (5 or 6 fields typical for cron)
  defp validate_cron_expression(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      cron ->
        parts = String.split(cron, " ", trim: true)
        if length(parts) >= 5 do
          changeset
        else
          add_error(changeset, field, "must be a valid cron expression with at least 5 fields")
        end
    end
  end
end
