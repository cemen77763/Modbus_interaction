-module(gen_modbus).

-type proplists() :: 
    atom() | tuple().


-callback init(Args :: term()) ->
    {ok, State :: term()} | {ok, State :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term()} | ignore.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()},
                      State :: term()) ->
    {reply, Reply :: term(), NewState :: term()} |
    {reply, Reply :: term(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Reply :: term(), NewState :: term()} |
    {stop, Reason :: term(), NewState :: term()}.

-callback handle_cast(Request :: term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), NewState :: term()}.

-callback handle_info(Info :: timeout | term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), NewState :: term()}.

-callback handle_continue(Info :: term(), State :: term()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), NewState :: term()}.

-callback connect(State :: term(), NetInfo :: proplists() |
                 {error, Reason :: term()}) ->
    {ok, NewState :: term(), NetInfo :: term()} | 
    {stop, Reason :: term(), NewState :: term()}.

-callback disconnect(State :: term(), Reason :: term()) ->
    {ok, NewState :: term()} | 
    {stop, Reason :: term(), NewState :: term()}.

-callback message(RegisterInfo :: list() | {error, Reason :: term()}, State :: term()) ->
    {reply, Reply :: term(), NewState :: term()} | 
    {noreply, NewState :: term()} | 
    {stop, NewState :: term()}.



-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) -> 
    term().

-optional_callbacks([terminate/2]).


-behaviour(gen_server).

% API
-export([
    start_link/3,
    start_link/4,
    cast/2,
    call/2,
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
    handle_continue/2, 
    terminate/2, 
    code_change/3]).

-include("modbus_functional_codes.hrl").

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
    gen_server:start_link(?MODULE, [Mod, Args], Options).


start_link(Name, Mod, Args, Options) ->
    gen_server:start_link(Name, ?MODULE, [Mod, Args], Options).


cast(Name, Message) ->
    gen_server:cast(Name, Message).


call(Name, Message) ->
    gen_server:call(Name, Message).


stop(Name) ->
    gen_server:stop(Name).


try_connect(Name, NetInfo) ->
    gen_server:call(Name, {try_connect, NetInfo}).      


try_disconnect(Name) ->
    gen_server:cast(Name, {try_disconnect}).


read_register(Name, RegisterInfo) ->
    gen_server:cast(Name, {read, RegisterInfo}).


write_register(Name, RegisterInfo) ->
    gen_server:cast(Name, {write, RegisterInfo}).


init([Mod, Args]) ->
    case init_it(Mod, Args) of
        {ok, {ok, State}} ->  
            {ok, #state{mod = Mod, state = State}};

        {ok, {ok, State, Timeout}} ->    
            {ok, #state{mod = Mod, state = State}, Timeout};

        {ok, {stop, Reason}} ->
            {stop, Reason};

        {ok, ignore} ->
            ignore;

        {ok, Else} ->
            Else;

        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)
    
    end.

handle_continue(Info, State) ->
    Mod = State#state.mod,
    case try_continue(Mod, Info, State#state.state) of
        {ok, {noreply, NewState}} ->
            {noreply, State#state{state = NewState}};

        {ok, {noreply, NewState, Timeout}} ->
            {noreply, State#state{state = NewState}, Timeout};

        {ok, {stop, Reason, NewState}} ->
            {stop, Reason, State#state{state = NewState}}
            
    end.


handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};


handle_call({try_connect, [Ip_addr, Port]}, _From, State) ->
    Mod = State#state.mod,
    case try_reconnect(State, [Ip_addr, Port]) of
        {error, Reason} ->
            case connect_it(Mod, {error, Reason}, State) of
                {ok, {ok, NewState, NetInfo}} ->
                    {reply, NetInfo, State#state{state = NewState}};

                {ok, {stop, Reason, NewState}} ->
                    {stop, Reason, State#state{state = NewState}};

                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)

            end;
        NewState ->
            case connect_it(Mod, {connected, Ip_addr, Port}, NewState) of
                {ok, {ok, NState, NetInfo}} ->
                    {reply, NetInfo, NewState#state{state = NState}};
                
                {ok, {stop, Reason, NState}} ->
                    {stop, Reason, NewState#state{state = NState}};

                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            
            end
    end;

handle_call(Request, From, State) ->
    Mod = State#state.mod,
    case try_call(Mod, Request, From, State#state.state) of
        {ok, {reply, Reply, NewState}} ->
            {reply, Reply, State#state{state = NewState}};

        {ok, {reply, Reply, NewState, Timeout}} ->
            {reply, Reply, State#state{state = NewState}, Timeout};

        {ok, {noreply, NewState}} ->
            {noreply, State#state{state = NewState}};

        {ok, {noreply, NewState, Timeout}} ->
            {noreply, State#state{state = NewState}, Timeout};

        {ok, {stop, Reason, Reply, NewState}} ->
            {stop, Reason, Reply, State#state{state = NewState}};

        {ok, {stop, Reason, NewState}} ->
            {stop, Reason, State#state{state = NewState}}
            
    end.


handle_cast({try_disconnect}, State) ->
    Mod = State#state.mod,
    Socket = State#state.modbus_state#modbusTCP.socket,
    if Socket =/= 0 ->
        gen_tcp:close(State#state.modbus_state#modbusTCP.socket);
        true ->
            ok
    end,

    case disconnect_it(Mod, State) of
        {ok, {ok, NState}} ->
            {noreply, State#state{state = NState, modbus_state = #modbusTCP{socket = 0, connection = close}}};
                
        {ok, {stop, Reason, NState}} ->
            {stop, Reason, State#state{state = NState, modbus_state = #modbusTCP{socket = 0, connection = close}}};

        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)

    end;

handle_cast({read, {holding_register, Dev_num, Reg_num}}, State) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, 1:16>>,
    Socket = State#state.modbus_state#modbusTCP.socket,
    Mod = State#state.mod,

    if Socket =/= 0 ->

        % Modbus код функции 03 (чтение Holding reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                reading_holding_register(Socket, State, [Dev_num, Reg_num]),
                {noreply, State};

            {error, _Reason} -> 
                try 
                    {ok, Mod:message({error, cant_send}, State#state.state)}

                catch 
                    throw:R -> {ok, R};
                    Class:R:S -> {'EXIT', Class, R, S}
            
                end, 
                {noreply, State}

        end;

    true -> 
        try
            Mod:message({error, socket_closed}, State#state.state)
                
        catch 
            throw:R -> {ok, R};
            Class:R:S -> {'EXIT', Class, R, S}
    
        end, 
        {noreply, State}

    end;

handle_cast({read, {holding_register, Dev_num, Reg_num, Quantity}}, State) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,
    Socket = State#state.modbus_state#modbusTCP.socket,
    Mod = State#state.mod,

    if Socket =/= 0 ->

        % Modbus код функции 03 (чтение Holding reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                reading_holding_registers(Socket, State, [Dev_num, Reg_num, Quantity]),
                {noreply, State};

            {error, _Reason} -> 
                try
                    Mod:message({error, cant_send}, State#state.state)
                        
                catch 
                    throw:R -> {ok, R};
                    Class:R:S -> {'EXIT', Class, R, S}
            
                end, 
                {noreply, State}

        end;

    true -> 
        try
            Mod:message({error, socket_closed}, State#state.state)
                
        catch 
            throw:R -> {ok, R};
            Class:R:S -> {'EXIT', Class, R, S}
    
        end, 
        {noreply, State}

    end;

handle_cast({read, {input_register, Dev_num, Reg_num, Quantity}}, State) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, Quantity:16>>,
    Socket = State#state.modbus_state#modbusTCP.socket,
    Mod = State#state.mod,

    if Socket =/= 0 ->

        % Modbus код функции 04 (чтение нескольких Input regs)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                reading_input_registers(Socket, State, [Dev_num, Reg_num, Quantity]),
                {noreply, State};

            {error, _Reason} -> 
                try
                    Mod:message({error, cant_send}, State#state.state)
                        
                catch 
                    throw:R -> {ok, R};
                    Class:R:S -> {'EXIT', Class, R, S}
            
                end, 
                {noreply, State}

        end;

    true -> 
        try 
            Mod:message({error, socket_closed}, State#state.state)
                
        catch 
            throw:R -> {ok, R};
            Class:R:S -> {'EXIT', Class, R, S}
    
        end, 
        {noreply, State}

    end;

handle_cast({read, {coil_status, Dev_num, Reg_num}}, State) ->
    Packet = <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16>>,
    Socket = State#state.modbus_state#modbusTCP.socket,
    Mod = State#state.mod,

    if Socket =/= 0 ->

        % Modbus код функции 01 (чтение нескольких Coil status)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                reading_coil_status(Socket, State, [Dev_num, Reg_num]),
                {noreply, State};

            {error, _Reason} -> 
                try 
                    Mod:message({error, cant_send}, State#state.state)
                        
                catch 
                    throw:R -> {ok, R};
                    Class:R:S -> {'EXIT', Class, R, S}
            
                end, 
                {noreply, State}

        end;

    true -> 
        try
            Mod:message({error, socket_closed}, State#state.state)
                
        catch 
            throw:R -> {ok, R};
            Class:R:S -> {'EXIT', Class, R, S}
    
        end, 
        {noreply, State}

    end;

handle_cast({write, {holding_register, Dev_num, Reg_num, Values}}, State) ->
    Socket = State#state.modbus_state#modbusTCP.socket,
    Mod = State#state.mod,

    if Socket =/= 0 ->
        Reg_quantity = length(Values),
        Len = Reg_quantity * 2,
    
        Packet_without_values = <<1:16, 0:16, 16#0B:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
        PacketMsg = list_to_bin16(Values, Packet_without_values),

        % Modbus код функции 10 (запись нескольких Holding regs)
        case gen_tcp:send(Socket, PacketMsg) of
            ok ->
                writing_holding_register(Socket, State, [Dev_num, Reg_num, Values]),
                {noreply, State};

            {error, _Reason} -> 
                try
                    Mod:message({error, cant_send}, State#state.state)
                        
                catch 
                    throw:R -> {ok, R};
                    Class:R:S -> {'EXIT', Class, R, S}
            
                end, 
                {noreply, State}

        end;
    true -> 
        try
            Mod:message({error, socket_closed}, State#state.state)
                
        catch 
            throw:R -> {ok, R};
            Class:R:S -> {'EXIT', Class, R, S}
    
        end, 
        {noreply, State}

    end;

handle_cast(Msg, State) ->
    Mod = State#state.mod,
    case try_cast(Mod, Msg, State#state.state) of
        {ok, {noreply, NewState}} ->
            {noreply, State#state{state = NewState}};

        {ok, {noreply, NewState, Timeout}} ->
            {noreply, State#state{state = NewState}, Timeout};

        {ok, {stop, Reason, NewState}} ->
            {stop, Reason, State#state{state = NewState}}
            
    end.


handle_info(Info, State) ->
    Mod = State#state.mod,
    case try_info(Mod, Info, State#state.state) of
        {ok, {noreply, NewState}} ->
            {noreply, State#state{state = NewState}};

        {ok, {noreply, NewState, Timeout}} ->
            {noreply, State#state{state = NewState}, Timeout};

        {ok, {stop, Reason, NewState}} ->
            {stop, Reason, State#state{state = NewState}}
            
    end.


terminate(Reason, State) ->
    Mod = State#state.mod,
    try_terminate(Mod, Reason, State#state.state),
    Socket = State#state.modbus_state#modbusTCP.socket,
    if Socket =/= 0 ->
        gen_tcp:close(State#state.modbus_state#modbusTCP.socket);
        true ->
            ok
    end,
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


% -------------------------------------------------------------------------------


init_it(Mod, Args) ->
    try
        {ok, Mod:init(Args)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.

try_continue(Mod, Info, State) ->
    try
        {ok, Mod:handle_continue(Info, State)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.

try_call(Mod, Request, From, State) ->
    try
        {ok, Mod:handle_call(Request, From, State#state.state)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.

try_cast(Mod, Msg, State) ->
    try
        {ok, Mod:handle_cast(Msg, State#state.state)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.

try_info(Mod, Info, State) ->
    try
        {ok, Mod:handle_info(Info, State#state.state)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.


connect_it(Mod, NetInfo, State) ->
    try
        {ok, Mod:connect(State#state.state, NetInfo)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.

disconnect_it(Mod, State) ->
    try
        {ok, Mod:disconnect(State#state.state, your_own)}

    catch 
        throw:R -> {ok, R};
        Class:R:S -> {'EXIT', Class, R, S}

    end.


try_terminate(Mod, Reason, State) ->
    case erlang:function_exported(Mod, terminate, 2) of
	true ->
	    try
		    {ok, Mod:terminate(Reason, State)}
	    
        catch
		    throw:R ->
            {ok, R};
            
		Class:R:Stacktrace ->
            {'EXIT', Class, R, Stacktrace}
            
        end;
	false ->
        {ok, ok}
        
    end.


reading_holding_register(Socket, State, [Dev_num, Reg_num]) ->
    Mod = State#state.mod,

    case gen_tcp:recv(Socket, 0, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, 5:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, 2:8, Reg_value:16>> = Data,
            try 
                Mod:message({holding_register, Dev_num, Reg_num, Reg_value}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end;

        {error, Reason} ->
            try
                Mod:message({error, Reason}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end

    end.


reading_holding_registers(Socket, State, [Dev_num, Reg_num, _Quantity]) ->
    Mod = State#state.mod,

    case gen_tcp:recv(Socket, 0, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, _:8, BinData/binary>> = Data,
            LData = bin_to_list16(BinData, []),
            try
                Mod:message({holding_register, Dev_num, Reg_num, LData}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end;

        {error, Reason} ->
            try
                Mod:message({error, Reason}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end

    end.


reading_input_registers(Socket, State, [Dev_num, Reg_num, _Quantity]) ->
    Mod = State#state.mod,

    case gen_tcp:recv(Socket, 0, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, _:8, BinData/binary>> = Data,
            LData = bin_to_list16(BinData, []),
            try
                Mod:message({input_register, Dev_num, Reg_num, LData}, State#state.state)
                        
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end;

        {error, Reason} ->
            try
                Mod:message({error, Reason}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end

    end.


reading_coil_status(Socket, State, [Dev_num, Reg_num]) ->
    Mod = State#state.mod,

    case gen_tcp:recv(Socket, 0, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Reg_value/binary>> = Data,
            try
                Mod:message({coils_status, Dev_num, Reg_num, Reg_value}, State#state.state)
                        
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end;

        {error, Reason} ->
            try
                Mod:message({error, Reason}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end

    end.


writing_holding_register(Socket, State, [Dev_num, Reg_num, Values]) ->
    Mod = State#state.mod,
    Quantity = length(Values),

    case gen_tcp:recv(Socket, 0, 3000) of
        {ok, Data} -> 
            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, _:16, Quantity:16>> = Data,
            try
                Mod:message({holding_register, Dev_num, Reg_num, Values, Quantity}, State#state.state)
                        
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end;

        {error, Reason} ->
            try
                Mod:message({error, Reason}, State#state.state)
                    
            catch 
                throw:R -> {ok, R};
                Class:R:S -> {'EXIT', Class, R, S}
        
            end

    end.


try_reconnect(State, [Ip_addr, Port]) ->
    % Поодключение к Modbus TCP устройству
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, ?SOCK_OPTS) of
        {ok, _} ->
            State#state{modbus_state = #modbusTCP{socket = Socket, connection = connect,
                                                ip_addr = Ip_addr, port = Port}};

        {error, Reason} ->
            {error, Reason}

    end.


list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).


bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);

bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).