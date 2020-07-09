-module(modbusTCP).


-callback init_modbus(List :: list()) ->
    {ok, State :: term(), NetInfo :: list()} | {ok, State :: term(), NetInfo :: term(), timeout()} |
    {stop, Reason :: term()} | ignore.

-callback connect(State :: term()) ->
    {ok, NewState :: term(), NewNetInfo :: list()} | {stop, Reason :: term(), NewState :: term()} | {error, Reason :: term()}.

-callback disconnect(State :: term()) ->
    {ok, NewState :: term()} | {stop, NewState :: term()}.

-callback message(RegisterInfo :: list(), State :: term()) ->
    {reply, Reply :: term(), NewState :: term()} | {noreply, NewState :: term()} | {stop, NewState :: term()}.


-behaviour(gen_server).

-include("modbus_functional_codes.hrl").

% API
-export([
    start_link/3,
    start_link/4,
    try_connect/2,
    try_disconnect/1,
    stop/1,
    read_register/2,
    write_register/2]).

% gen_server callbacks
-export([
    init/1,
    handle_call/3, 
    handle_cast/2, 
    handle_info/2, 
    terminate/2, 
    code_change/3]).

-record(modbusTCP, {
        socket = 0,
        connection = close,
        ip_addr = "localhost",
        port = 502}).

-record(state, {
        state = 0,
        mod :: atom(),
        modbus_state = #modbusTCP{}}).

-define(SOCK_OPTS, [binary, 
    {active, false},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}]).


start_link(Mod, Args, Options) ->
    gen_server:start_link(Mod, [Mod, Args], Options).


start_link(Name, Mod, Args, Options) ->
    gen_server:start_link(Name, ?MODULE, [Mod, Args], Options).


stop(Name) ->
    gen_server:stop(Name).

try_connect(Name, NetInfo) ->
    gen_server:cast(Name, {try_connect, NetInfo}).      

try_disconnect(Name) ->
    gen_server:cast(Name, {try_disconnect}).

read_register(Name, RegisterInfo) ->
    gen_server:cast(Name, {read, RegisterInfo}).

write_register(Name, RegisterInfo) ->
    gen_server:cast(Name, {write, RegisterInfo}).


init([Mod, Args]) ->
    {ok, {ok, State, [Ip_addr, Port]}} = 
    try
        {ok, Mod:init_modbus(Args)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end, 
    {ok, #state{modbus_state = #modbusTCP{ip_addr = Ip_addr, port = Port}, state = State, mod = Mod}}.


handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({try_connect, [Ip_addr, Port]}, State) ->
    Mod = State#state.mod,
    NewState = try_reconnect(State, [Ip_addr, Port]),
    {ok, {ok, ModbusState, _NetInfo}} = 
    try
        {ok, Mod:connect(State#state.state)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end, 
    
    {noreply, NewState#state{state = ModbusState}};

handle_cast({try_disconnect}, State) ->
    Mod = State#state.mod,
    gen_tcp:close(State#state.modbus_state#modbusTCP.socket),

    try
        {ok, Mod:disconnect(State#state.state)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end, 
    
    {noreply, State#state{modbus_state = #modbusTCP{socket = 0, connection = close}}};

handle_cast({read, {holding_register, Dev_num, Reg_num}}, State) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, 1:16>>,
    Socket = State#state.modbus_state#modbusTCP.socket,
    if Socket =/= 0 ->
        Mod = State#state.mod,

        % Modbus код функции 03 (чтение Holding reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                reading_holding_register(Socket, State, [Dev_num, Reg_num]),
                {noreply, State};

            {error, _Reason} -> 
                Mod:message([error, "can't send message"], State#state.state),
                {noreply, State}

        end;
    true -> {noreply, State}

    end;

handle_cast({write, {holding_register, Dev_num, Reg_num, Values}}, State) ->
    Socket = State#state.modbus_state#modbusTCP.socket,
    if Socket =/= 0 ->
        Reg_quantity = length(Values),
        Len = Reg_quantity * 2,
    
        Packet_without_values = <<1:16, 0:16, 16#0B:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
        PacketMsg = list_to_bin16(Values, Packet_without_values),
        Mod = State#state.mod,

        % Modbus код функции 03 (чтение Holding reg)
        case gen_tcp:send(Socket, PacketMsg) of
            ok ->
                writing_holding_register(Socket, State, [Dev_num, Reg_num, Values]),
                {noreply, State};

            {error, _Reason} -> 
                Mod:message([error, "can't send message"], State#state.state),
                {noreply, State}

        end;
    true -> {noreply, State}

    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

% ------------------------------------------------------------------------

reading_holding_register(Socket, State, [Dev_num, Reg_num]) ->
    Mod = State#state.mod,

    case gen_tcp:recv(Socket, 11, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, 5:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, 2:8, Reg_value:16>> = Data,
            Mod:message([Dev_num, Reg_num, Reg_value], State#state.state);

        {error, Reason} ->
            Mod:message([error, Reason], State#state.state)

    end.

writing_holding_register(Socket, State, [Dev_num, Reg_num, Values]) ->
    Mod = State#state.mod,
    Quantity = length(Values),

    case gen_tcp:recv(Socket, 12, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, _:16, Quantity:16>> = Data,
            Mod:message([Dev_num, Reg_num, Values, Quantity], State#state.state);

        {error, Reason} ->
            Mod:message([error, Reason], State#state.state)

    end.

try_reconnect(State, [Ip_addr, Port]) ->
    % Поодключение к Modbus TCP устройству
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, ?SOCK_OPTS) of
        {ok, _} ->
            State#state{modbus_state = #modbusTCP{socket = Socket, connection = connect,
                                                ip_addr = Ip_addr, port = Port}};

        {error, _Reason} ->
            try_reconnect(State, [Ip_addr, Port])

    end.

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).

