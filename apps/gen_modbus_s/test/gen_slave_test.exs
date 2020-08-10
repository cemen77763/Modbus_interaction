defmodule GenSlaveTest do
  use ExUnit.Case
    require Record

    Record.defrecord(:s,
        state: :state,
        stage: :init,
        mod: :alarm_panel,
        device: 2,
        listen_sock: :lsock,
        active_socks: [:sock],
        buff: %{}
        )
end
