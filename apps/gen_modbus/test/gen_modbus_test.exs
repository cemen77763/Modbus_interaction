defmodule GenModbusTest do
    use ExUnit.Case
    require Record
    Record.defrecord(:sock_info,
        socket: 1,
        port: 502)

    Record.defrecord(:state,
        state: :undefined,
        mod: :modbus_tcp,
        sock_info: :undefined,
        sock_opts: :undefined,
        stream: :undefined,
        stage: :disconnect
        )

    test "отсановка gen_modbus" do
        assert :gen_modbus.stop(:gen_modbus) == :ok
    end

    test "получение ответа от slave целиком" do
        # Modbus код функции 03 (чтение Holding reg)
        assert :gen_modbus.handle_info({:tcp, :socket, <<2::16, 0::16, 7::16, 1::8, 3::8, 4::8, 25::16, 2::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 04 (чтение Input reg)
        assert :gen_modbus.handle_info({:tcp, :socket, <<23::16, 0::16, 7::16, 1::8, 4::8, 4::8, 16::16, 32::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 01 (чтение Coils status)
        assert :gen_modbus.handle_info({:tcp, :socket, <<1::16, 0::16, 4::16, 1::8, 1::8, 1::8, 22::8>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 02 (чтение Inputs status)
        assert :gen_modbus.handle_info({:tcp, :socket, <<13::16, 0::16, 4::16, 3::8, 2::8, 1::8, 1::8>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 10 (запись Holding reg)
        assert :gen_modbus.handle_info({:tcp, :socket, <<13::16, 0::16, 6::16, 3::8, 16::8, 1::16, 5::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 05 (запись Coil status)
        assert :gen_modbus.handle_info({:tcp, :socket, <<13::16, 0::16, 6::16, 3::8, 5::8, 12::16, 0::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 0f (запись Coils status)
        assert :gen_modbus.handle_info({:tcp, :socket, <<13::16, 0::16, 6::16, 2::8, 15::8, 3::16, 4::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        # Modbus код функции 06 (запись Holding reg)
        assert :gen_modbus.handle_info({:tcp, :socket, <<1::16, 0::16, 6::16, 1::8, 6::8, 1::16, 55::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}
    end

    test "получение ответа от slave по частям" do
        assert :gen_modbus.handle_info({:tcp, :socket, <<1::16, 0::16>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:protocol, <<1::16, 0::16>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<0::8>>}, state(stream: {:protocol, <<1::16, 0::16>>})) ==
        {:noreply, state(stream: {:protocol, <<1::16, 0::16, 0::8>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<16::8>>}, state(stream: {:protocol, <<1::16, 0::16, 0::8>>})) ==
        {:noreply, state(stream: {:msglen, <<1::16, 0::16, 16::16>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<6::16, 1::8, 6::8>>}, state(stream: {:protocol, <<1::16, 0::16>>})) ==
        {:noreply, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<3::16, 55::16>>}, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}
    end

    test "получение ответа от slave по неравномерным частям" do
        assert :gen_modbus.handle_info({:tcp, :socket, <<0::8>>}, state(stream: {:waiting, <<>>})) ==
        {:noreply, state(stream: {:waiting, <<0::8>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<1::8, 0::16>>}, state(stream: {:waiting, <<0::8>>})) ==
        {:noreply, state(stream: {:protocol, <<1::16, 0::16>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<0::4, 0::9, 6::3, 1::8, 6::8>>}, state(stream: {:protocol, <<1::16, 0::16>>})) ==
        {:noreply, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<3::8>>}, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8>>})) ==
        {:noreply, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8, 3::8>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<55::16>>}, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8, 3::8>>})) ==
        {:noreply, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8, 3::8, 55::16>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<3::8, 23::16>>}, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8, 3::8>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<12::8>>}, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8, 5::16, 23::8>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}

        assert :gen_modbus.handle_info({:tcp, :socket, <<12::8, 5::16, 0::16>>}, state(stream: {:fun_code, 6, <<1::16, 0::16, 6::16, 1::8, 6::8, 5::16, 23::8>>})) ==
        {:noreply, state(stream: {:waiting, <<>>})}
    end
end
