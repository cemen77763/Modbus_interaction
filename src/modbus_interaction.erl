%%% ----------------------------------------------------------------------- %%%
%%% author: Kekeev Semyon (s.kekeev@g.nsu.ru)                               %%%
%%% description: This module implements interaction with devices according  %%%
%%% to the Modbus TCP protocol                                              %%%
%%% ----------------------------------------------------------------------- %%%

-module(modbus_interaction).

%% Интерфейс
-export([start_link/0,
        start_link/1,
        close_connection/0,
        read_Hreg/2,
        read_Hregs/3, 
        read_Ireg/2,
        read_Iregs/3,
        read_Creg/2,
        read_Isreg/2,
        write_Creg/3,
        write_Hreg/3,
        write_Hregs/3
        ]).

%% Для внутреннего использования
-export([connect/2]).
 
-include("modbus_functional_codes.hrl").  

-define(PORT, 502).

-define(IP_ADDR, "localhost").

-define(SOCK_OPTS, [binary, 
                    {active, true},
                    {packet, raw},
                    {reuseaddr, true},
                    {nodelay, true}]).


start_link() ->
    Pid = spawn(?MODULE, connect, [?IP_ADDR, ?PORT]),
    register(?MODULE, Pid).


start_link(Ip_addr) when is_tuple(Ip_addr) ->
    Pid = spawn(?MODULE, connect, [Ip_addr, ?PORT]),
    register(?MODULE, Pid).


%% Подключение к Modbus TCP серверу
connect(Host, Port) -> 
    case {_, Socket} = gen_tcp:connect(Host, Port, ?SOCK_OPTS) of
        {ok, _} -> 
            io:format("Connection fine...~n"),
            loop(Socket);
        {error, Reason} -> 
            error_logger:error_msg("~w: connection failed because ~w~n", [?MODULE, Reason]),
            timer:sleep(1000),
            connect(Host, Port)
    end.


loop(Socket) ->
    receive
        
        % Modbus код функции 03 (чтение Holding reg)
        {readH, _Pid, Msg} ->
            [Device_num, First_reg_num] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_HREGS:8, First_reg_num:16, 1:16>>) of
                ok -> 
                    io:format("Trying read device #~w, holding register #~w~n", [Device_num, First_reg_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't read holding register because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        % Modbus код функции 03 (чтение нескольких Holding regs)
        {readsH, _Pid, Msg} ->
            [Device_num, First_reg_num, Quantity] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_HREGS:8, First_reg_num:16, Quantity:16>>) of
                ok ->
                    io:format("Trying read ~w Holding registers in device #~w~n", [Quantity, Device_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't read holding registers because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        % Modbus код функции 06 (запись Holding reg)
        {writeH, _Pid, Msg} ->
            [Device_num, First_reg_num, Var] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_WRITE_HREG:8, First_reg_num:16, Var:16>>) of
                ok ->
                    io:format("Trying rewrire device #~w, Holding registers #~w~n", [Device_num, First_reg_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't write holding register because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        % Modbus код функции 10 (запись нескольких Holding regs)
        {writesH, _Pid, Msg} ->
            [Device_num, First_reg_num, Values] = Msg,
            Reg_quantity = length(Values),
            Len = Reg_quantity * 2,

            Packet_without_values = <<1:16, 0:16, 16#0B:16, Device_num:8,
                            ?FUN_CODE_WRITE_HREGS:8, First_reg_num:16, Reg_quantity:16, Len:8>>,
            PacketMsg = bin_conversion:list_to_bin16(Values, Packet_without_values),

            case gen_tcp:send(Socket, PacketMsg) of
                ok ->
                    io:format("Trying rewrire device #~w, Holding register #~w, values: ~w~n", [Device_num, First_reg_num, Values]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't write holding registers because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        % Modbus код функции 04 (чтение Input reg)
        {readI, _Pid, Msg} ->
            [Device_num, First_reg_num] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_IREGS:8, First_reg_num:16, 1:16>>) of
                ok ->
                    io:format("Trying read device #~w, Input register #~w~n", [Device_num, First_reg_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't read input register because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        % Modbus код функции 04 (чтение нескольких Input regs)
        {readsI, _Pid, Msg} ->
            [Device_num, First_reg_num, Quantity] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_IREGS:8, First_reg_num:16, Quantity:16>>) of
                ok ->
                    io:format("Trying read ~w Input registers in device #~w~n", [Quantity, Device_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't read input registers because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);
        
        % Modbus код функции 05 (запись Coil status)
        {writeC, _Pid, Msg} ->
            [Device_num, First_reg_num, Value] = Msg,

            Var = 
            case Value of
                0 -> <<0:16>>;
                1 -> <<16#FF:8, 0:8>>;
                _ ->
                    error_logger:error_msg("Wrong value ~w~n", [Value]),
                    {error, wrong_value}
            end,

            if Var =/= {error, wrong_value} ->
                case gen_tcp:send(Socket, <<1:16, 0:16, 6:16, Device_num:8,
                                ?FUN_CODE_WRITE_COIL:8, First_reg_num:16, Var:16>>) of
                    ok ->
                        io:format("Trying write ~w Input status in device #~w~n", [Var, Device_num]);
                    {error, Reason} -> 
                        error_logger:error_msg("Can't read input status because ~w~n", [Reason]),
                        gen_tcp:close(Socket),
                        connect(?IP_ADDR, ?PORT)
                end
            end,

            loop(Socket);



        % Modbus код функции 01 (чтение Coil status)
        {readC, _Pid, Msg} ->
            [Device_num, First_reg_num] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 4:16, Device_num:8,
                            ?FUN_CODE_READ_COILS:8, First_reg_num:16>>) of
                ok ->
                    io:format("Trying read device #~w, Coil status #~w~n", [Device_num, First_reg_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't read coil status because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        % Modbus код функции 02 (чтение Input status)
        {readIs, _Pid, Msg} ->
            [Device_num, First_reg_num] = Msg,

            case gen_tcp:send(Socket, <<1:16, 0:16, 4:16, Device_num:8,
                            ?FUN_CODE_READ_INPUTS:8, First_reg_num:16>>) of
                ok ->
                    io:format("Trying read device #~w, Input status #~w~n", [Device_num, First_reg_num]);
                {error, Reason} -> 
                    error_logger:error_msg("Can't read input status because ~w~n", [Reason]),
                    gen_tcp:close(Socket),
                    connect(?IP_ADDR, ?PORT)
            end,

            loop(Socket);

        {tcp, Socket, Msg} ->
            case Msg of 

                %% ----------------------------------УСПЕХ---------------------------------
                % Произошло успешное чтение Holding reg 
                <<1:16, 0:16, 5:16, _Device_num:8, ?FUN_CODE_READ_HREGS:8, 2:8, Data:16>> ->
                    io:format("Data in single register is  ~w~n", [Data]);

                % Произошла успешная запись Holding reg 
                <<1:16, 0:16, 6:16, _Device_num:8, ?FUN_CODE_WRITE_HREG:8, _:16, Var:16>> -> 
                    io:format("~w writed in register~n", [Var]);

                % Произошла успешная запись Holding regs
                <<1:16, 0:16, 6:16, _Device_num:8, ?FUN_CODE_WRITE_HREGS:8, _:16, Quantity:16>> -> 
                    io:format("~w bytes was written~n", [Quantity]);

                % Произошло успешное чтение Holding regs
                <<1:16, 0:16, _:16, _Device_num:8, ?FUN_CODE_READ_HREGS:8, _:8, Data/binary>> ->
                    %Переделать binary to integer (сейчас Data binary)
                    io:format("Data in registers is ~w~n", [Data]);

                % Произошло успешное чтение Input reg
                <<1:16, 0:16, 5:16, _Device_num:8, ?FUN_CODE_READ_IREGS:8, 2:8, Data:16>> ->
                    io:format("Data in single register is  ~w~n", [Data]);

                % Произошло успешное чтение Input regs 
                <<1:16, 0:16, _:16, _Device_num:8, ?FUN_CODE_READ_IREGS:8, _:8, Data/binary>> ->
                    %Переделать binary to integer (сейчас Data binary)
                    io:format("Data in registers is ~w~n", [Data]);

                % Произошло успешное чтение Coil status 
                <<1:16, 0:16, 4:16, _Device_num:8, ?FUN_CODE_READ_COILS:8, 1:8, Data>> ->
                    io:format("Data in coils status is  ~w~n", [Data]);

                % Произошло успешное чтение Input status
                <<1:16, 0:16, 4:16, _Device_num:8, ?FUN_CODE_READ_INPUTS:8, 1:8, Data>> ->
                    io:format("Data in input status is  ~w~n", [Data]);

                % Произошла успешная запись Coil status
                <<1:16, 0:16, 6:16, _Device_num:8, ?FUN_CODE_WRITE_COIL:8, _:16, Var:16>> ->
                    io:format("~w writed in register~n", [Var]);

                %% ----------------------------------НЕУДАЧА--------------------------------
                % Ошибка чтения Coil status 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка чтения Input status 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка чтения Holding regs 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка чтения Input regs 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка записи Coils status 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка записи Holding reg 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка записи Coil status 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Ошибка записи Holding regs 
                <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>> ->
                    decrypton_error_code:decrypt(Err_code);

                % Неизвестное TCP сообщение
                Other -> 
                    error_logger:error_msg("Error: Process ~w got unknown tcp msg ~w~n.", [self(), Other])
            
            end,
            loop(Socket);

        % Сервер закрыл соединение 
        {tcp_closed, Socket} ->
            gen_tcp:close(Socket),
            error_logger:error_msg("Error: ~w was closed.", [Socket]),
            connect(?IP_ADDR, ?PORT);

        % Закрытие соединения
        {close, ok} ->
            gen_tcp:close(Socket),
            unregister(?MODULE),
            io:format("Connection was closed.~n");

        % Неизвестное сообщение
        Other -> 
            error_logger:error_msg("Error: Process ~w got unknown msg ~w~n.", [self(), Other]),
            loop(Socket)

    end.


%% Отправка сообщения для прочтения 1 Holding reg
read_Hreg(Device_num, Reg_num) ->
    erlang:send(?MODULE, {readH, self(), [Device_num, Reg_num]}),
    ok.


%% Отправка сообщения для прочтения N Holding regs
read_Hregs(Device_num, Reg_num, Quantity) ->
    erlang:send(?MODULE, {readsH, self(), [Device_num, Reg_num, Quantity]}),
    ok.


%% Отправка сообщения для записи 1 Holding reg
write_Hreg(Device_num, Reg_num, Var) ->
    erlang:send(?MODULE, {writeH, self(), [Device_num, Reg_num, Var]}),
    ok.


%% Отправка сообщения для записи N Holding regs
write_Hregs(Device_num, Reg_num, Values) when is_list(Values) ->
    erlang:send(?MODULE, {writesH, self(), [Device_num, Reg_num, Values]}),
    ok.


%% Отправка сообщения для прочтения 1 Input regs
read_Ireg(Device_num, Reg_num) ->
    erlang:send(?MODULE, {readI, self(), [Device_num, Reg_num]}),
    ok.


%% Отправка сообщения для прочтения N Input regs
read_Iregs(Device_num, Reg_num, Quantity) ->
    erlang:send(?MODULE, {readsI, self(), [Device_num, Reg_num, Quantity]}),
    ok.


%% Отправка сообщения для записи Coil status
write_Creg(Device_num, Reg_num, Value) ->
    erlang:send(?MODULE, {writeC, self(), [Device_num, Reg_num, Value]}),
    ok.


%% Отправка сообщения для прочтения Coil status
read_Creg(Device_num, Reg_num) ->
    erlang:send(?MODULE, {readC, self(), [Device_num, Reg_num]}),
    ok.


%% Отправка сообщения для прочтения Input status
read_Isreg(Device_num, Reg_num) ->
    erlang:send(?MODULE, {readIs, self(), [Device_num, Reg_num]}),
    ok.


%% Отравка сообщения для закрытия соединения с Modbus TCP сервером
close_connection() ->
    erlang:send(?MODULE, {close, ok}),
    ok.




