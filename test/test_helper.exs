ExUnit.configure(exclude: [:integration, :load, :nats_live])
ExUnit.start()

Mox.defmock(BotArmyJobScheduler.ScheduleStoreMock,
  for: BotArmyJobScheduler.ScheduleStoreBehaviour
)
