defmodule GenModbusTest do
    use ExUnit.Case
    require Record

    Record.defrecord(:state,
        state: :state,
        mod: :modbus_master,
        sock_info: Record.defrecord(:sock_info,
            socket: :undefined,
            ip_addr: :undefined,
            port: :undefined
            ),
        sock_opts: :undefined,
        recv_buff: <<>>,
        send_buff: <<>>,
        stage: :init
        )

    test "test handle" do
        assert :gen_master.handle_call(:msg, self(), state()) == {:reply, :msg, state()}
        assert :gen_master.handle_continue(:msg, state()) == {:noreply, state()}
        assert :gen_master.handle_info(:msg, state()) == {:noreply, state()}
        assert :gen_master.handle_cast(:msg, state()) == {:noreply, state()}
    end

    test "Modbus код функции 03 (чтение Holding reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<2::16, 0::16, 7::16, 1::8, 3::8, 4::8, 25::16, 2::16>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 04 (чтение Input reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<23::16, 0::16, 7::16, 1::8, 4::8, 4::8, 16::16, 32::16>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 01 (чтение Coils status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 4::16, 1::8, 1::8, 1::8, 22::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 02 (чтение Inputs status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<13::16, 0::16, 4::16, 3::8, 2::8, 1::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 10 (запись Holding reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<13::16, 0::16, 6::16, 3::8, 16::8, 1::16, 5::16>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 05 (запись Coil status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<13::16, 0::16, 6::16, 3::8, 5::8, 12::16, 0::16>>}, state()) ==
        {:noreply, state()}
        assert :gen_master.handle_info({:tcp, :undefined, <<13::16, 0::16, 6::16, 3::8, 5::8, 12::16, 255::8, 0::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 0f (запись Coils status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<13::16, 0::16, 6::16, 2::8, 15::8, 3::16, 4::16>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код функции 06 (запись Holding reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 6::16, 1::8, 6::8, 1::16, 32::16>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 81 (чтение Coil status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 129::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 82 (чтение Input status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 130::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 83 (чтение Holding reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 131::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 84 (чтение Input reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 132::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 85 (запись Coil status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 133::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 86 (запись Holding reg)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 134::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 8f (запись Coils status)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 143::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "Modbus код ошибки 90 (запись Holding regs)" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 3::16, 1::8, 144::8, 1::8>>}, state()) ==
        {:noreply, state()}
    end

    test "получение ответа от slave по частям" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16>>}, state()) ==
        {:noreply, state(recv_buff: <<1::16, 0::16>>)}

        assert :gen_master.handle_info({:tcp, :undefined, <<0::8>>}, state(recv_buff: <<1::16, 0::8>>)) ==
        {:noreply, state(recv_buff: <<1::16, 0::16>>)}

        assert :gen_master.handle_info({:tcp, :undefined, <<40::16, 1::16, 0::16, 6::16, 1::8, 6::8, 1::16, 55::16, 1::16>>}, state(recv_buff: <<1::16, 0::16, 6::16, 1::8, 6::8, 1::16>>)) ==
        {:noreply, state(recv_buff: <<1::16>>)}

        assert :gen_master.handle_info({:tcp, :undefined, <<16::8>>}, state(recv_buff: <<1::16, 0::16, 0::8>>)) ==
        {:noreply, state(recv_buff: <<1::16, 0::16, 16::16>>)}

        assert :gen_master.handle_info({:tcp, :undefined, <<6::16, 1::8, 6::8>>}, state(recv_buff: <<1::16, 0::16, 16::16>>)) ==
        {:noreply, state(recv_buff: <<1::16, 0::16, 16::16, 6::16, 1::8, 6::8>>)}

        assert :gen_master.handle_info({:tcp, :undefined, <<40::16>>}, state(recv_buff: <<1::16, 0::16, 6::16, 1::8, 6::8, 1::16>>)) ==
        {:noreply, state(recv_buff: <<>>)}
    end

    test "получение двух склееных ответов от slave" do
        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 6::16, 1::8, 6::8, 1::16, 55::16, 1::16, 0::16, 6::16, 1::8, 6::8, 1::16, 55::16, 8::16, 1::8>>}, state()) ==
        {:noreply, state(recv_buff: <<8::16, 1::8>>)}

        assert :gen_master.handle_info({:tcp, :undefined, <<1::16, 0::16, 6::16, 1::8, 6::8, 1::16, 55::16, 1::16, 0::16, 3::16, 1::8, 144::8, 1::8, 34::24>>}, state()) ==
        {:noreply, state(recv_buff: <<34::24>>)}
    end
end
