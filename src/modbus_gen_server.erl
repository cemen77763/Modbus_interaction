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
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3,
    try_reconnect/1,
    list_to_bin16/2]).

-define(SERVER, modbus_gen).

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
    State = #state{ip_addr = ?IP_ADDR, port = ?PORT},
    erlang:send(self(), try_connect),
    {ok, State}.


handle_call({#function.read_hreg, [Device_num, Reg_num]}, _From, State) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, 1:16>>,

    % Modbus код функции 03 (чтение Holding reg)
    case gen_tcp:send(State#state.socket, Packet) of

        ok -> 
            error_logger:info_msg("Trying read device #~w, holding register #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read holding register because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.read_hregs, [Device_num, Reg_num, Quantity]}, _From, State) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,

    % Modbus код функции 03 (чтение нескольких Holding regs)
    case gen_tcp:send(State#state.socket, Packet) of
                
        ok ->
            error_logger:info_msg("Trying read ~w Holding registers in device #~w~n", [Quantity, Device_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read holding registers because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.write_hreg, [Device_num, Reg_num, Var]}, _From, State) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Var:16>>,

    % Modbus код функции 06 (запись Holding regs)
    case gen_tcp:send(State#state.socket, Packet) of
                
        ok ->
            error_logger:info_msg("Trying rewrire device #~w, Holding registers #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't write holding register because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.write_hregs, [Device_num, Reg_num, Values]}, _From, State) ->
    % Modbus код функции 10 (запись нескольких Holding regs)
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,

    Packet_without_values = <<1:16, 0:16, 16#0B:16, Device_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    PacketMsg = list_to_bin16(Values, Packet_without_values),

    case gen_tcp:send(State#state.socket, PacketMsg) of
                
        ok ->
            error_logger:info_msg("Trying rewrire device #~w, Holding register #~w, values: ~w~n", [Device_num, Reg_num, Values]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't write holding registers because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.read_ireg, [Device_num, Reg_num]}, _From, State) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, 1:16>>,

    % Modbus код функции 04 (чтение Input reg)
    case gen_tcp:send(State#state.socket, Packet) of

        ok -> 
            error_logger:info_msg("Trying read device #~w, Input register #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input register because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.read_iregs, [Device_num, Reg_num, Quantity]}, _From, State) ->
    Packet = <<1:16, 0:16, 6:16, Device_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, Quantity:16>>,

    % Modbus код функции 04 (чтение нескольких Input regs)
    case gen_tcp:send(State#state.socket, Packet) of

        ok -> 
            error_logger:info_msg("Trying read ~w Input registers in device #~w~n", [Quantity, Device_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input registers because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.write_coil, [Device_num, Reg_num, Value]}, _From, State) ->
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
            case gen_tcp:send(State#state.socket, Packet) of
                        
                ok ->
                    error_logger:info_msg("Trying write ~w Coil status in device #~w~n", [Var, Device_num]),
                    {reply, ok, State};

                {error, Reason} -> 
                    error_logger:error_msg("Can't read Coil status because ~w~n", [Reason]),
                    gen_tcp:close(State#state.socket),
                    {ok, Socket} = try_reconnect(State),
                    {reply, error, State#state{socket = Socket, connection = connect}}

            end;

        true -> 
            {reply, error, State}

    end;

handle_call({#function.read_coil, [Device_num, Reg_num]}, _From, State) ->
    Packet = <<1:16, 0:16, 4:16, Device_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16>>,

    % Modbus код функции 01 (чтение Coil status)
    case gen_tcp:send(State#state.socket, Packet) of

        ok -> 
            error_logger:info_msg("Trying read device #~w, Coil status #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read coil status because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call({#function.read_inputs, [Device_num, Reg_num]}, _From, State) ->
    Packet = <<1:16, 0:16, 4:16, Device_num:8, ?FUN_CODE_READ_INPUTS:8, Reg_num:16>>,

    % Modbus код функции 02 (чтение Input status)
    case gen_tcp:send(State#state.socket, Packet) of

        ok -> 
            error_logger:info_msg("Trying read device #~w, Input status #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input status because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            {ok, Socket} = try_reconnect(State),
            {reply, error, State#state{socket = Socket, connection = connect}}

    end;

handle_call(_Msg, From, State) ->
    error_logger:error_msg("Error: Got unknown message from ~w~n.", [From]),
    {reply, unknown_message, State}.


handle_cast(_Msg, State) ->
    error_logger:error_msg("Error: Got unknown message~n."),
    {noreply, State}.


handle_info(try_connect, State) ->
    {ok, Socket} = try_reconnect(State),
    {noreply, State#state{socket = Socket, connection = connect}};

handle_info({tcp, _Socket, Msg}, State) ->
    ReturnMsg = 
    case Msg of 

        %% ----------------------------------УСПЕХ-------------------------------- %%
        % Произошло успешное чтение Holding reg 
        <<1:16, 0:16, 5:16, _Device_num:8, ?FUN_CODE_READ_HREGS:8, 2:8, Data:16>> ->
            error_logger:info_msg("Data in single register is  ~w~n", [Data]),
            {#function.read_hreg, Data};

        % Произошла успешная запись Holding reg 
        <<1:16, 0:16, 6:16, _Device_num:8, ?FUN_CODE_WRITE_HREG:8, _:16, Var:16>> -> 
            error_logger:info_msg("~w writed in register~n", [Var]),
            {#function.write_hreg, Var};

        % Произошла успешная запись Holding regs
        <<1:16, 0:16, 6:16, _Device_num:8, ?FUN_CODE_WRITE_HREGS:8, _:16, Quantity:16>> -> 
            error_logger:info_msg("~w bytes was written~n", [Quantity]),
            {#function.write_hregs, Quantity};

        % Произошло успешное чтение Holding regs
        <<1:16, 0:16, _:16, _Device_num:8, ?FUN_CODE_READ_HREGS:8, _:8, Data/binary>> ->
            %Переделать binary to integer (сейчас Data binary)
            error_logger:info_msg("Data in registers is ~w~n", [Data]),
            {#function.read_hregs, Data};

        % Произошло успешное чтение Input reg
        <<1:16, 0:16, 5:16, _Device_num:8, ?FUN_CODE_READ_IREGS:8, 2:8, Data:16>> ->
            error_logger:info_msg("Data in single register is  ~w~n", [Data]),
            {#function.read_ireg, Data};

        % Произошло успешное чтение Input regs 
        <<1:16, 0:16, _:16, _Device_num:8, ?FUN_CODE_READ_IREGS:8, _:8, Data/binary>> ->
            %Переделать binary to integer (сейчас Data binary)
            error_logger:info_msg("Data in registers is ~w~n", [Data]),
            {#function.read_iregs, Data};

        % Произошло успешное чтение Coil status 
        <<1:16, 0:16, 4:16, _Device_num:8, ?FUN_CODE_READ_COILS:8, 1:8, Data>> ->
            error_logger:info_msg("Data in coils status is  ~w~n", [Data]),
            {#function.read_coil, Data};

        % Произошло успешное чтение Input status
        <<1:16, 0:16, 4:16, _Device_num:8, ?FUN_CODE_READ_INPUTS:8, 1:8, Data>> ->
            error_logger:info_msg("Data in input status is  ~w~n", [Data]),
            {#function.read_inputs, Data};

        % Произошла успешная запись Coil status
        <<1:16, 0:16, 6:16, _Device_num:8, ?FUN_CODE_WRITE_COIL:8, _:16, Var:16>> ->
            error_logger:info_msg("~w writed in register~n", [Var]),
            {#function.write_coil, Var};

        %% ----------------------------------НЕУДАЧА-----------------------------  %%
        % Ошибка чтения Coil status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.read_coil, error};

        % Ошибка чтения Input status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.read_inputs, error};

        % Ошибка чтения Holding regs 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.read_hregs, error};

        % Ошибка чтения Input regs 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.read_iregs, error};

        % Ошибка записи Coils status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.read_coil, error};

        % Ошибка записи Holding reg 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.write_hreg, error};

        % Ошибка записи Coil status 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.write_coil, error};

        % Ошибка записи Holding regs 
        <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>> ->
            decryption_error_code:decrypt(Err_code),
            {#function.write_hregs, error};

        % Неизвестное TCP сообщение
        Other -> 
            error_logger:error_msg("Error: Got unknown tcp message ~w~n.", [Other]),
            {unknown}
    end,

    {noreply, State#state{register_info = ReturnMsg}};

handle_info({tcp_closed, _Socket}, State) ->
    gen_tcp:close(State#state.socket),
    error_logger:error_msg("Error: ~w was closed.", [State#state.socket]),
    {ok, Socket} = try_reconnect(State),
    {noreply, State#state{socket = Socket, connection = connect}};

handle_info(Msg, State) ->
    error_logger:error_msg("Error: Got unknown message ~w~n.", [Msg]),
    {noreply, State}.


terminate(_, State) ->
    gen_tcp:close(State#state.socket),
    ok.


code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% ----------------------------------------------------------------- %%

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).


try_reconnect(State) ->
    
    % Поодключение к Modbus TCP устройству
    case {_, Socket} = gen_tcp:connect(State#state.ip_addr, State#state.port, ?SOCK_OPTS) of

        {ok, _} ->
            error_logger:info_msg("Connection fine...~n"),
            {ok, Socket};
        
        {error, Reason} -> 
            error_logger:error_msg("~w: connection failed because ~w~n", [?MODULE, Reason]),
            try_reconnect(State)

    end.
