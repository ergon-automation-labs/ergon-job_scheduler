defmodule BotArmyJobScheduler.Repo.Migrations.AddAwayModeSieveSchedule do
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO schedules (id, title, description, cron_expression, command, timeout, status, inserted_at, updated_at)
    VALUES (
      gen_random_uuid(),
      'Away-Mode Sieve',
      'Process health snapshots and store digests in KV at 12:00 UTC',
      '00 12 * * *',
      'ops.away_mode_sieve.run',
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
    DELETE FROM schedules WHERE command = 'ops.away_mode_sieve.run';
    """)
  end
end
