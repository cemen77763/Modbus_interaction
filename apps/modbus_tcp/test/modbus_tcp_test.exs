defmodule ModbusTcpTest do
  use ExUnit.Case

  test "stop gen_modbus" do
    assert :modbus_tcp.stop() == :ok
  end
end
