defmodule GenModbusTest do
  use ExUnit.Case

  test "stop gen_modbus" do
    assert :gen_modbus.stop(:gen_modbus) == :ok
  end
end
