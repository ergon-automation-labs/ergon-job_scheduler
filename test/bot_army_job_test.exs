defmodule BotArmyJobTest do
  use ExUnit.Case
  doctest BotArmyJob

  test "version" do
    assert BotArmyJob.version() == "0.1.0"
  end
end
