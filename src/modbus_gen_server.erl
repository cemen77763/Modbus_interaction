%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc Server for connecting to Modbus TCP devices                                          %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(modbus_gen_server).

-behaviour(gen_server).

-include("modbus_functional_codes.hrl").
 
-record(state, {
    socket = 0,
    ip_addr = "localhost",
    port = 502,
    connection = closed,
    register_info = unknown}).

-export([
    start_link/0,
    init/1,
    handle_continue/2,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, modbus_gen).

-define(STORAGE, storage_server).

-define(PORT, 502).

-define(IP_ADDR, "localhost").

-define(SOCK_OPTS, [binary, 
                    {active, true},
                    {packet, raw},
                    {reuseaddr, true},
                    {nodelay, true}]).


start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


init([]) ->
    S = #state{ip_addr = ?IP_ADDR, port = ?PORT},
    {ok, S, {continue, try_connect}}.


handle_continue(try_connect, S) ->
    {noreply, try_reconnect(S)}.


handle_call(#read_hreg{device_num = Dev_num, register_num = Reg_num}, _From, S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, 1:16>>,

    % Modbus код функции 03 (чтение Holding reg)
    case gen_tcp:send(S#state.socket, Packet) of
        ok -> 
            error_logger:info_msg("Trying read device #~w, holding register #~w~n", [Dev_num, Reg_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't read holding register because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(#read_hregs{device_num = Device_num, register_num = Reg_num, quantity = Quantity}, _From, S) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,

    % Modbus код функции 03 (чтение нескольких Holding regs)
    case gen_tcp:send(S#state.socket, Packet) of                
        ok ->
            error_logger:info_msg("Trying read ~w holding registers in device #~w~n", [Quantity, Device_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't read holding registers because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(#write_hreg{device_num = Device_num, register_num = Reg_num, value = Value}, _From, S) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>,

    % Modbus код функции 06 (запись Holding regs)
    case gen_tcp:send(S#state.socket, Packet) of               
        ok ->
            error_logger:info_msg("Trying rewrire device #~w, holding registers #~w~n", [Device_num, Reg_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't write holding register because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(#write_hregs{device_num = Device_num, register_num = Reg_num, values = Values}, _From, S) ->
    % Modbus код функции 10 (запись нескольких Holding regs)
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,

    Packet_without_values = <<1:16, 0:16, 16#0B:16, Device_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    PacketMsg = list_to_bin16(Values, Packet_without_values),

    case gen_tcp:send(S#state.socket, PacketMsg) of           
        ok ->
            error_logger:info_msg("Trying rewrire device #~w, holding register #~w, values: ~w~n", [Device_num, Reg_num, Values]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't write holding registers because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(#read_ireg{device_num = Device_num, register_num = Reg_num}, _From, S) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, 1:16>>,

    % Modbus код функции 04 (чтение Input reg)
    case gen_tcp:send(S#state.socket, Packet) of
        ok -> 
            error_logger:info_msg("Trying read device #~w, input register #~w~n", [Device_num, Reg_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input register because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(#read_iregs{device_num = Device_num, register_num = Reg_num, quantity = Quantity}, _From, S) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, Quantity:16>>,

    % Modbus код функции 04 (чтение нескольких Input regs)
    case gen_tcp:send(S#state.socket, Packet) of
        ok -> 
            error_logger:info_msg("Trying read ~w input registers in device #~w~n", [Quantity, Device_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input registers because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(#write_coil{device_num = Device_num, register_num = Reg_num, value = Value}, _From, S) ->
    % Modbus код функции 05 (запись Coil status)
    Var = 
        case Value of
            0 -> <<0:16>>;
            1 -> <<16#FF:8, 0:8>>;
            _ ->
                error_logger:error_msg("Wrong value ~w~n", [Value]),
                    {error, wrong_value}
        end,

    if 
        Var =/= {error, wrong_value} -> 
            Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var/binary>>,
            case gen_tcp:send(S#state.socket, Packet) of                       
                ok ->
                    error_logger:info_msg("Trying write ~w coil status in device #~w~n", [Var, Device_num]),
                    {reply, ok, S};

                {error, Reason} -> 
                    error_logger:error_msg("Can't read Coil status because ~w~n", [Reason]),
                    gen_tcp:close(S#state.socket),
                    {reply, error, try_reconnect(S)}

            end;

        true -> 
            {reply, error, S}

    end;

handle_call(#read_coil{device_num = Device_num, register_num = Reg_num}, _From, S) ->
    Packet = <<1:16, 0:16, 4:16, Device_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16>>,

    % Modbus код функции 01 (чтение Coil status)
    case gen_tcp:send(S#state.socket, Packet) of
        ok -> 
            error_logger:info_msg("Trying read device #~w, coil status #~w~n", [Device_num, Reg_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't read coil status because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}
        
    end;

handle_call(#read_inputs{device_num = Device_num, register_num = Reg_num}, _From, S) ->
    Packet = <<1:16, 0:16, 4:16, Device_num:8, ?FUN_CODE_READ_INPUTS:8, Reg_num:16>>,

    % Modbus код функции 02 (чтение Input status)
    case gen_tcp:send(S#state.socket, Packet) of
        ok -> 
            error_logger:info_msg("Trying read device #~w, input status #~w~n", [Device_num, Reg_num]),
            {reply, ok, S};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input status because ~w~n", [Reason]),
            gen_tcp:close(S#state.socket),
            {reply, error, try_reconnect(S)}

    end;

handle_call(_Msg, From, S) ->
    error_logger:error_msg("Got unknown message from ~w~.n", [From]),
    {reply, unknown_message, S}.


handle_cast(_Msg, S) ->
    error_logger:error_msg("Got unknown message.~n"),
    {noreply, S}.


handle_info({tcp, _Socket, Msg}, S) ->
    case Msg of 

        %% ----------------------------------УСПЕХ-------------------------------- %%
        % Произошло успешное чтение Holding reg 
        <<1:16, 0:16, 5:16, Device_num:8, ?FUN_CODE_READ_HREGS:8, 2:8, Data:16>> ->
            gen_server:call(?STORAGE, {#read_hreg{device_num = Device_num}, Data});

        % Произошла успешная запись Holding reg 
        <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_WRITE_HREG:8, _:16, Var:16>> -> 
            gen_server:call(?STORAGE, {#write_hreg{device_num = Device_num}, Var});

        % Произошла успешная запись Holding regs
        <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_WRITE_HREGS:8, _:16, Quantity:16>> -> 
            gen_server:call(?STORAGE, {#write_hregs{device_num = Device_num}, Quantity});

        % Произошло успешное чтение Holding regs
        <<1:16, 0:16, _:16, Device_num:8, ?FUN_CODE_READ_HREGS:8, _:8, Data/binary>> ->
            LData = bin_to_list16(Data, []),
            gen_server:call(?STORAGE, {#read_hregs{device_num = Device_num}, LData});

        % Произошло успешное чтение Input reg
        <<1:16, 0:16, 5:16, Device_num:8, ?FUN_CODE_READ_IREGS:8, 2:8, Data:16>> ->
            gen_server:call(?STORAGE, {#read_ireg{device_num = Device_num}, Data});

        % Произошло успешное чтение Input regs 
        <<1:16, 0:16, _:16, Device_num:8, ?FUN_CODE_READ_IREGS:8, _:8, Data/binary>> ->
            LData = bin_to_list16(Data, []),
            gen_server:call(?STORAGE, {#read_iregs{device_num = Device_num}, LData});

        % Произошло успешное чтение Coil status 
        <<1:16, 0:16, 4:16, Device_num:8, ?FUN_CODE_READ_COILS:8, 1:8, Data>> ->
            gen_server:call(?STORAGE, {#read_coil{device_num = Device_num}, Data});

        % Произошло успешное чтение Input status
        <<1:16, 0:16, 4:16, Device_num:8, ?FUN_CODE_READ_INPUTS:8, 1:8, Data>> ->
            gen_server:call(?STORAGE, {#read_inputs{device_num = Device_num}, Data});

        % Произошла успешная запись Coil status
        <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_WRITE_COIL:8, _:16, Var:16>> ->
            gen_server:call(?STORAGE, {#write_coil{device_num = Device_num}, Var});

        %% ----------------------------------НЕУДАЧА-----------------------------  %%
        % Ошибка чтения Coil status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка чтения Input status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка чтения Holding regs 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка чтения Input regs 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка записи Coils status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка записи Holding reg 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка записи Coil status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Ошибка записи Holding regs 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code);

        % Неизвестное TCP сообщение
        Other -> 
            error_logger:error_msg("Got unknown tcp message ~w~n.", [Other])

    end,

    {noreply, S};

handle_info({tcp_closed, _Socket}, S) ->
    gen_tcp:close(S#state.socket),
    error_logger:error_msg("~w was closed.", [S#state.socket]),
    {noreply, try_reconnect(S)};

handle_info(Msg, S) ->
    error_logger:error_msg("Got unknown message ~w~n.", [Msg]),
    {noreply, S}.


terminate(_Reason, S) ->
    gen_tcp:close(S#state.socket),
    ok.


code_change(_OldVsn, S, _Extra) ->
    {ok, S}.


%% ----------------------------------------------------------------- %%

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).


bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);

bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).


try_reconnect(S, _) ->
    % Поодключение к Modbus TCP устройству
    case {_, Socket} = gen_tcp:connect(S#state.ip_addr, S#state.port, ?SOCK_OPTS) of
        {ok, _} ->
            error_logger:info_msg("Connection fine...~n"),
            S#state{socket = Socket, connection = connect};

        {error, _Reason} ->
            try_reconnect(S, 1)

    end.


try_reconnect(S) ->
    % Поодключение к Modbus TCP устройству
    case {_, Socket} = gen_tcp:connect(S#state.ip_addr, S#state.port, ?SOCK_OPTS) of
        {ok, _} ->
            error_logger:info_msg("Connection fine...~n"),
            S#state{socket = Socket, connection = connect};

        {error, _Reason} ->
            error_logger:error_msg("Connection established.~n"), 
            try_reconnect(S, 1)

    end.


