defmodule ModbusMasterTest do
    use ExUnit.Case
    require Record

    Record.defrecord(:sock_info,
        socket: :undefined,
        ip_addr: 'localhost',
        port: 502)

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
        register_number: 1,
        registers_value: 0,
        error_code: :undefined)

    Record.defrecord(:write_coils_status,
        transaction_id: 1,
        device_number: 2,
        register_number: 2,
        quantity: 4,
        registers_value: 15,
        error_code: :undefined)

    test "init" do
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
    end

    test "disconnect" do
        assert :modbus_master.disconnect(:normal, :state) == {:ok, [], :state}
    end

    test "start/stop application" do
        assert :modbus_master.stop() == :ok
        assert :modbus_master.start() == {:ok, :pid} #!!!!!!!!
    end

    test "handle" do
        assert :modbus_master.handle_call(:msg, self(), :state) == {:reply, :msg, [], :state}
        assert :modbus_master.handle_continue(:msg, :state) == {:noreply, [], :state}
        assert :modbus_master.handle_info(:msg, :state) == {:noreply, [], :state}
        assert :modbus_master.handle_cast(:msg, :state) == {:noreply, [], :state}
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
        {:ok, [write_coils_status(register_number: 0, registers_value: 1)], :state}

        assert :modbus_master.message(write_coils_status(), :state) ==
        {:ok, [read_register(type: :holding)], :state}
    end

    test "terminate" do
        assert :modbus_master.terminate(:shutdown, :state) == :ok
    end
end
