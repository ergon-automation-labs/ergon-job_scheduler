defmodule BotArmyJobScheduler.Repo.Migrations.CreateHeartbeats do
  use Ecto.Migration

  def change do
    create table(:heartbeats, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:bot_id, :string, null: false)
      add(:service, :string, null: false)
      add(:tenant_id, :binary_id, null: false)
      add(:source, :string, null: false)
      add(:status, :string, null: false)
      add(:uptime_seconds, :integer)
      add(:last_event_age_ms, :integer)
      add(:sequence, :integer)
      add(:payload, :jsonb, null: false, default: "{}")
      add(:recorded_at, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:heartbeats, [:bot_id]))
    create(index(:heartbeats, [:tenant_id]))
    create(index(:heartbeats, [:service]))
    create(unique_index(:heartbeats, [:service, :tenant_id], name: :heartbeats_service_tenant_unique))
  end
end
