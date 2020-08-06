defmodule GenMasterTest do
  use ExUnit.Case
  doctest GenMaster

  test "greets the world" do
    assert GenMaster.hello() == :world
  end
end
