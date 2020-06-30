%%% ----------------------------------------------------------------------- %%%
%%% author: Kekeev Semyon (s.kekeev@g.nsu.ru)                               %%%
%%% @doc This module implements interaction with devices according          %%%
%%% @doc to the Modbus TCP protocol                                         %%%
%%% ----------------------------------------------------------------------- %%%

-module(modbus_interaction).

%% Интерфейс
-export([start/0,
        close_connection/0,
        read_Hreg/2,
        read_Hregs/3, 
        read_Ireg/2,
        read_Iregs/3,
        read_Creg/2,
        read_Isreg/2,
        write_Creg/3,
        write_Hreg/3,
        write_Hregs/3,
        connect/2,
        loop/1
        ]).
 
-include("modbus_functional_codes.hrl").

-define(SERVER, modbus).

-define(PORT, 502).

-define(IP_ADDR, "localhost").

-define(SOCK_OPTS, [binary, 
                    {active, true},
                    {packet, raw},
                    {reuseaddr, true},
                    {nodelay, true}]).


start() ->
    modbus_gen_server:start_link().

connect(_A, _B) ->
    ok.

loop(Socket) ->
    receive

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
    gen_server:call(?SERVER, {readH, [Device_num, Reg_num]}),
    ok.


%% Отправка сообщения для прочтения N Holding regs
read_Hregs(Device_num, Reg_num, Quantity) ->
    gen_server:call(?SERVER, {readsH, [Device_num, Reg_num, Quantity]}),
    ok.


%% Отправка сообщения для записи 1 Holding reg
write_Hreg(Device_num, Reg_num, Var) ->
    gen_server:call(?SERVER, {writeH, [Device_num, Reg_num, Var]}),
    ok.


%% Отправка сообщения для записи N Holding regs
write_Hregs(Device_num, Reg_num, Values) when is_list(Values) ->
    gen_server:call(?SERVER, {writesH, [Device_num, Reg_num, Values]}),
    ok.


%% Отправка сообщения для прочтения 1 Input regs
read_Ireg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, {readI, [Device_num, Reg_num]}),
    ok.


%% Отправка сообщения для прочтения N Input regs
read_Iregs(Device_num, Reg_num, Quantity) ->
    gen_server:call(?SERVER, {readsI, [Device_num, Reg_num, Quantity]}),
    ok.


%% Отправка сообщения для записи Coil status
write_Creg(Device_num, Reg_num, Value) ->
    gen_server:call(?SERVER, {writeC, [Device_num, Reg_num, Value]}),
    ok.


%% Отправка сообщения для прочтения Coil status
read_Creg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, {readC, [Device_num, Reg_num]}),
    ok.


%% Отправка сообщения для прочтения Input status
read_Isreg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, {readIs, [Device_num, Reg_num]}),
    ok.


%% Отравка сообщения для закрытия соединения с Modbus TCP сервером
close_connection() ->
    gen_server:call(?SERVER, {close, ok}),
    ok.




