defmodule BotArmyJobScheduler.Repo.Migrations.AddHealthCheckerSchedule do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO schedules (id, title, description, cron_expression, command, timeout, status, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Health Checker',
      'Daily fleet health snapshot at 11:50 UTC',
      '50 11 * * *',
      'ops.health_checker.run',
      30,
      'active',
      NOW(),
      NOW()
    )
    ON CONFLICT DO NOTHING;
    """)
  end

  def down do
    execute("""
    DELETE FROM schedules WHERE command = 'ops.health_checker.run';
    """)
  end
end
