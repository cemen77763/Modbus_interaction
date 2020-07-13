defmodule GenModbusTest do
  use ExUnit.Case
  doctest GenModbus

  test "greets the world" do
    assert GenModbus.hello() == :world
  end
end
