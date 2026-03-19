defmodule BotArmyJobScheduler.Repo.Migrations.CreateSchedules do
  use Ecto.Migration

  def change do
    create table(:schedules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :title, :string, null: false
      add :description, :text
      add :cron_expression, :string, null: false
      add :command, :string, null: false
      add :timeout, :integer, default: 3600, null: false
      add :status, :string, default: "active", null: false
      add :last_run_at, :naive_datetime

      timestamps()
    end

    create index(:schedules, [:status])
    create index(:schedules, [:cron_expression])
  end
end
