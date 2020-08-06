defmodule ModbusTcpTest do
    use ExUnit.Case
    require Record

    Record.defrecord(:sock_info,
        socket: :undefined,
        ip_addr: 'localhost',
        port: 502)

    Record.defrecord(:s,
        s: :state,
        allowed_connections: 5,
        active_socks: [:socket])

    Record.defrecord(:disconnect,
        reason: :normal)

    Record.defrecord(:connect,
        ip_addr: 'localhost',
        port: 5000)

    Record.defrecord(:change_sock_opts,
        reuseaddr: :true,
        nodelay: :true,
        ifaddr: :undefined)

    Record.defrecord(:read_register,
        type: :undefined,
        transaction_id: 1,
        device_number: 2,
        register_number: 1,
        quantity: 5,
        registers_value: :undefined,
        error_code: :undefined)

    Record.defrecord(:read_status,
        type: :undefined,
        transaction_id: 1,
        device_number: 2,
        register_number: 1,
        quantity: 5,
        registers_value: :undefined,
        error_code: :undefined)

    Record.defrecord(:write_holding_register,
        transaction_id: 1,
        device_number: 2,
        register_number: 1,
        registers_value: 12,
        error_code: :undefined)

    Record.defrecord(:write_holding_registers,
        transaction_id: 1,
        device_number: 2,
        register_number: 2,
        registers_value: [13, 14, 15, 16],
        error_code: :undefined)

    Record.defrecord(:write_coil_status,
        transaction_id: 1,
        device_number: 2,
        register_number: 3,
        registers_value: 1,
        error_code: :undefined)

    Record.defrecord(:write_coils_status,
        transaction_id: 1,
        device_number: 2,
        register_number: 2,
        quantity: 4,
        registers_value: 15,
        error_code: :undefined)

    test "init" do
        assert :modbus_slave.init([]) == {:ok, [:wait_connect], s(active_socks: [])}
        assert :modbus_master.init([]) == {:ok, [change_sock_opts(), connect()], 5}
    end

    test "decryption error code" do
        assert :decryption_error_code.decrypt(1) == 1
        assert :decryption_error_code.decrypt(2) == 2
        assert :decryption_error_code.decrypt(3) == 3
        assert :decryption_error_code.decrypt(4) == 4
        assert :decryption_error_code.decrypt(5) == 5
        assert :decryption_error_code.decrypt(6) == 6
        assert :decryption_error_code.decrypt(7) == 7
        assert :decryption_error_code.decrypt(8) == 8
        assert :decryption_error_code.decrypt(10) == 10
        assert :decryption_error_code.decrypt(11) == 11
        assert :decryption_error_code.decrypt(:something) == :something
    end

    test "connect" do
        assert :modbus_master.connect(sock_info(), :state) ==
        {:ok, [write_holding_register()], :state}
        assert :modbus_slave.connect(:socket, s()) ==
        {:ok, [:wait_connect], s(allowed_connections: 4, active_socks: [:socket, :socket])}
        assert :modbus_slave.connect(:socket, s(allowed_connections: 0)) ==
        {:ok, [], s(allowed_connections: 0)}
    end

    test "disconnect" do
        assert :modbus_master.disconnect(:normal, :state) == {:ok, [], :state}
        assert :modbus_slave.disconnect(:socket, :normal, s(active_socks: [:socket])) ==
        {:ok, [:wait_connect], s(active_socks: [], allowed_connections: 6)}
    end

    test "start/stop application" do
        assert :modbus_slave.stop() == :ok
        assert :modbus_master.stop() == :ok
        assert :modbus_slave.start() == {:ok, :pid} #!!!!!!!!!
        assert :modbus_master.start() == {:ok, :pid} #!!!!!!!!
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
        assert :modbus_master.handle_call(:msg, self(), :state) == {:reply, :msg, [], :state}
        assert :modbus_master.handle_continue(:msg, :state) == {:noreply, [], :state}
        assert :modbus_master.handle_info(:msg, :state) == {:noreply, [], :state}
        assert :modbus_master.handle_cast(:msg, :state) == {:noreply, [], :state}

        assert :modbus_slave.handle_call(:msg, self(), :state) == {:reply, :msg, [], :state}
        assert :modbus_slave.handle_continue(:msg, :state) == {:noreply, [], :state}
        assert :modbus_slave.handle_info(:msg, :state) == {:noreply, [], :state}
        assert :modbus_slave.handle_cast(:msg, :state) == {:noreply, [], :state}
        assert :modbus_slave.handle_cast(:msg, :state) == {:noreply, [], :state}
    end

    test "message" do
        assert :modbus_master.message(:something, :state) ==
        {:ok, [], :state}

        assert :modbus_master.message(read_register(type: :holding, transaction_id: 1), :state) ==
        {:ok, [read_register(type: :input, device_number: 2, register_number: 1, quantity: 5, registers_value: :undefined)], :state}

        assert :modbus_master.message(read_register(type: :input), :state) ==
        {:ok, [read_status(type: :coil)], :state}

        assert :modbus_master.message(read_status(type: :input), :state) ==
        {:ok, [disconnect()], :state}

        assert :modbus_master.message(read_status(type: :coil), :state) ==
        {:ok, [read_status(type: :input, register_number: 12)], :state}

        assert :modbus_master.message(write_holding_register(), :state) ==
        {:ok, [write_holding_registers()], :state}

        assert :modbus_master.message(write_holding_registers(), :state) ==
        {:ok, [write_coil_status(registers_value: 0)], :state}

        assert :modbus_master.message(write_coil_status(), :state) ==
        {:ok, [write_coils_status()], :state}

        assert :modbus_master.message(write_coils_status(), :state) ==
        {:ok, [read_register(type: :holding)], :state}

        assert :modbus_slave.message({:alarm, :on, 2}, s()) ==
        {:ok, [], s()}

        assert :modbus_slave.message({:alarm, :off, 1}, s()) ==
        {:ok, [], s()}
    end

    test "master handle call alarm" do
        assert :modbus_master.handle_call({:alarm, 1}, :from, :state) == {:noreply, [write_coil_status(register_number: 1)], :state}
        assert :modbus_master.handle_call({:alarm, 2}, :from, :state) == {:noreply, [write_coil_status(register_number: 2)], :state}
        assert :modbus_master.handle_call({:alarm, 3}, :from, :state) == {:noreply, [write_coil_status(register_number: 3)], :state}
        assert :modbus_master.handle_call({:alarm, 4}, :from, :state) == {:noreply, [write_coil_status(register_number: 4)], :state}
        assert :modbus_master.handle_call({:alarm, 5}, :from, :state) == {:noreply, [write_coil_status(register_number: 5)], :state}
    end

    test "terminate" do
        assert :modbus_master.terminate(:shutdown, :state) == :ok
        assert :modbus_slave.terminate(:shutdown, :state) == :ok
    end
end
