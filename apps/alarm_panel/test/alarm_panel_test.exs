defmodule AlarmPanelTest do
    use ExUnit.Case
    require Record

    Record.defrecord(:undefined_code,
        response: :undefined
        )

    Record.defrecord(:s,
        coils: 0,
        allowed_connections: 5,
        active_socks: [:socket]
        )

    Record.defrecord(:disconnect,
        reason: :normal,
        socket: :undefined
        )

    test "init" do
        assert :alarm_panel.init([]) == {:ok, [:wait_connect], s(active_socks: [])}
    end

    test "connect" do
        assert :alarm_panel.connect(:socket, s()) ==
        {:ok, [:wait_connect], s(allowed_connections: 4, active_socks: [:socket, :socket])}
        assert :alarm_panel.connect(:socket, s(allowed_connections: 0)) ==
        {:ok, [], s(allowed_connections: 0)}
    end

    test "disconnect" do
        assert :alarm_panel.disconnect(:socket, :normal, s(active_socks: [:socket])) ==
        {:ok, [:wait_connect], s(active_socks: [], allowed_connections: 6)}
    end

    test "start/stop application" do
        assert :alarm_panel.stop() == :ok
        assert :alarm_panel.start() == {:ok, :pid} #!!!!!!!!!
    end

    test "alarm handle cast" do
        assert :gen_slave.cast(:gen_slave, {:alarm, :on, 1}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :on, 2}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :on, 3}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :on, 4}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :on, 5}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :off, 1}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :off, 2}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :off, 3}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :off, 4}) == :ok
        assert :gen_slave.cast(:gen_slave, {:alarm, :off, 5}) == :ok
        assert :gen_slave.cast(:gen_slave, :something) == :ok
    end

    test "handle" do
        assert :alarm_panel.handle_call(:msg, self(), :state) == {:reply, :msg, [], :state}
        assert :alarm_panel.handle_continue(:msg, :state) == {:noreply, [], :state}
        assert :alarm_panel.handle_info(:msg, :state) == {:noreply, [], :state}
        assert :alarm_panel.handle_cast(:msg, :state) == {:noreply, [], :state}
        assert :alarm_panel.handle_cast(:msg, :state) == {:noreply, [], :state}
    end

    test "terminate" do
        assert :alarm_panel.terminate(:shutdown, :state) == :ok
    end
end