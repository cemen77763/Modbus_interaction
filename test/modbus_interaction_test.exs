defmodule ModbusInteractionTest do
  use ExUnit.Case
  doctest ModbusInteraction

  test "greets the world" do
    assert ModbusInteraction.hello() == :world
  end
end
