defmodule BotArmyJobScheduler.Repo.Migrations.CreateHeartbeats do
  use Ecto.Migration

  def change do
    create table(:heartbeats, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :bot_id, :string, null: false
      add :service, :string, null: false
      add :tenant_id, :uuid, null: false
      add :source, :string
      add :status, :string, null: false
      add :uptime_seconds, :integer
      add :last_event_age_ms, :integer
      add :sequence, :integer
      add :payload, :jsonb
      add :recorded_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:heartbeats, [:service, :tenant_id])
    create index(:heartbeats, [:bot_id])
    create index(:heartbeats, [:tenant_id])
    create index(:heartbeats, [:service])
  end
end
