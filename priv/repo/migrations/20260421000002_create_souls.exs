defmodule BotArmyJobScheduler.Repo.Migrations.CreateSouls do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:souls, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:bot_id, :string, null: false)
      add(:tenant_id, :binary_id, null: false)
      add(:config, :jsonb, null: false, default: "{}")
      add(:version, :integer, null: false, default: 1)
      add(:active, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists(index(:souls, [:bot_id]))
    create_if_not_exists(index(:souls, [:tenant_id]))

    create_if_not_exists(
      index(:souls, [:bot_id, :tenant_id], unique: true, name: :souls_bot_tenant_unique)
    )
  end
end
