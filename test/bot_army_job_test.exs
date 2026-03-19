defmodule BotArmyJobSchedulerTest do
  use ExUnit.Case
  doctest BotArmyJobScheduler

  test "version" do
    assert BotArmyJobScheduler.version() == "0.1.0"
  end
end
