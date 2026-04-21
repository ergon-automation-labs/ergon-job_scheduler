defmodule BotArmyJobScheduler.Repo.Migrations.CreateSkillsAndActions do
  use Ecto.Migration

  def change do
    create table(:skills, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:name, :text, null: false)
      add(:slug, :text, null: false)
      add(:markdown_content, :text, null: false)
      add(:version, :integer, null: false, default: 1)
      add(:is_active, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime)
    end

    create(index(:skills, [:tenant_id, :slug, :version], unique: true))

    create(
      index(:skills, [:tenant_id, :slug, :is_active],
        unique: true,
        where: "is_active = true"
      )
    )

    create(
      index(:skills, [:tenant_id, :is_active],
        where: "is_active = true"
      )
    )

    create table(:tenant_actions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:tenant_id, :binary_id, null: false)
      add(:slug, :text, null: false)
      add(:type, :text, null: false)
      add(:config_json, :jsonb, null: false, default: "{}")
      add(:is_active, :boolean, null: false, default: true)

      timestamps(type: :utc_datetime)
    end

    create(index(:tenant_actions, [:tenant_id, :slug], unique: true))

    create(
      index(:tenant_actions, [:tenant_id, :is_active],
        where: "is_active = true"
      )
    )
  end
end
