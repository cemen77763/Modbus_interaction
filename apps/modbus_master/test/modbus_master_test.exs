defmodule ModbusMasterTest do
  use ExUnit.Case
  doctest ModbusMaster

  test "greets the world" do
    assert ModbusMaster.hello() == :world
  end
end
