defmodule ModbusTcpTest do
  use ExUnit.Case
  doctest ModbusTcp

  test "greets the world" do
    assert ModbusTcp.hello() == :world
  end
end
