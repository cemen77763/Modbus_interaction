defmodule GenSlaveTest do
  use ExUnit.Case
  doctest GenSlave

  test "greets the world" do
    assert GenSlave.hello() == :world
  end
end
