defmodule ModbusTcpTest do
    use ExUnit.Case
    require Record
    Record.defrecord(:read_holding_registers,
        device_number: 1,
        register_number: 2,
        quantity: 5,
        registers_value: [1, 4],
        error_code: :undefined)

    Record.defrecord(:read_input_registers,
        device_number: 5,
        register_number: 2,
        quantity: 5,
        registers_value: [1, 4],
        error_code: :undefined)

    Record.defrecord(:read_coils_status,
        device_number: 5,
        register_number: 2,
        quantity: 5,
        registers_value: [1, 4],
        error_code: :undefined)

    Record.defrecord(:read_inputs_status,
        device_number: 5,
        register_number: 2,
        quantity: 5,
        registers_value: [1, 4],
        error_code: :undefined)

    Record.defrecord(:write_holding_register,
        device_number: 5,
        register_number: 2,
        quantity: 5,
        registers_value: [1, 4],
        error_code: :undefined)

    Record.defrecord(:write_holding_registers,
        device_number: 5,
        register_number: 2,
        registers_value: [1, 4],
        quantity: :undefined,
        error_code: :undefined)

    Record.defrecord(:write_coil_status,
        device_number: 1,
        register_number: 1,
        quantity: 1,
        registers_value: :undefined,
        error_code: :undefined)

    Record.defrecord(:write_coils_status,
        device_number: 1,
        register_number: 1,
        quantity: 1,
        registers_value: 1,
        error_code: :undefined)

    test "test connect" do
        assert :modbus_tcp.connect(["localhost", 502], 5) == {:ok, [], 5}
    end

    test "test message" do
        assert :modbus_tcp.message(read_holding_registers(), 5) == {:ok, [], 5}
    end

    test "test disconnect" do
        assert :modbus_tcp.disconnect(:normal, 5) == {:ok, [], 5}
    end

    test "test handle call" do
        assert :modbus_tcp.handle_call(:msg, self(), 5) == {:reply, :msg, [], 5}
    end

    test "test handle continue" do
        assert :modbus_tcp.handle_continue(:msg, 5) == {:noreply, [], 5}
    end

    test "test handle info" do
        assert :modbus_tcp.handle_info(:msg, 5) == {:noreply, [], 5}
    end

    test "test handle cast" do
        assert :modbus_tcp.handle_cast(:msg, 5) == {:noreply, [], 5}
    end

    test "stop gen_modbus" do
        assert :modbus_tcp.stop() == :ok
    end
end
