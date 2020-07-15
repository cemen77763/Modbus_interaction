-module(gen_modbus).

-type cmd() :: record:records().

-type netinfo() :: proplists:proplists().


-callback init(Args :: term()) ->
    {ok, Command :: cmd(), State :: term()} | {ok, Command :: cmd(), State :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Command :: cmd(), Reason :: term()} | ignore.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) ->
    {reply, Reply :: term(), Command :: cmd(), NewState :: term()} |
    {reply, Reply :: term(), Command :: cmd(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {noreply, Command :: cmd(), NewState :: term()} |
    {noreply, Command :: cmd(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Reply :: term(), Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback handle_cast(Request :: term(), State :: term()) ->
    {noreply, Command :: cmd(), NewState :: term()} |
    {noreply, Command :: cmd(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback handle_info(Info :: timeout | term(), State :: term()) ->
    {noreply, Command :: cmd(), NewState :: term()} |
    {noreply, Command :: cmd(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback handle_continue(Info :: term(), State :: term()) ->
    {noreply, Command :: cmd(), NewState :: term()} |
    {noreply, Command :: cmd(), NewState :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback connect(State :: term(), NetInfo :: netinfo()) ->
    {ok, Command :: cmd(), NewState :: term()} | 
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback disconnect(State :: term(), Reason :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} | 
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback message(RegisterInfo :: proplists:proplists(), State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} | 
    {stop, Command :: cmd(), NewState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) -> 
    term().

-optional_callbacks([
    terminate/2, 
    handle_info/2,
    handle_continue/2
    ]).


-behaviour(gen_server).

% API
-export([
    start_link/3,
    start_link/4,
    cast/2,
    call/2,
    stop/1
    ]).

% gen_server callbacks
-export([
    init/1,
    handle_call/3, 
    handle_cast/2, 
    handle_info/2,
    handle_continue/2, 
    terminate/2, 
    code_change/3
    ]).

-include("../include/gen_modbus.hrl").

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary, 
    {active, false},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(socket_info, {
    socket = 0,
    connection = close,
    ip_addr = "localhost",
    port = 502
    }).

-record(state, {
    state = 0,
    mod :: atom(),
    socket_info = #socket_info{},
    socket_opts = ?DEFAULT_SOCK_OPTS
    }).

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

init([Mod, Args]) ->
    Res =
    try
        {ok, Mod:init(Args)}
    catch 
        throw:R -> {ok, R};
        C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {ok, Command, State}} ->  
            {ok, cmd(Command, #state{mod = Mod, state = State})};
        {ok, {ok, Command, State, Timeout}} ->    
            {ok, cmd(Command, #state{mod = Mod, state = State}), Timeout};
        {ok, {stop, Command, Reason}} ->
            cmd(Command, #state{mod = Mod}),
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
    Res =
    try
        {ok, Mod:handle_continue(Info, State#state.state)}
    catch 
        throw:R -> {ok, R};
        C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {noreply, Command, NewState}} ->
            {noreply, cmd(Command, State#state{state = NewState})};
        {ok, {noreply, Command, NewState, Timeout}} ->
            {noreply, cmd(Command, State#state{state = NewState}), Timeout};
        {ok, {stop, Reason, Command, NewState}} ->
            {stop, Reason, cmd(Command, State#state{state = NewState})};          
        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)          
    end.

handle_call(Request, From, State) ->
    Mod = State#state.mod,
    Res =
    try
        {ok, Mod:handle_call(Request, From, State#state.state)}
    catch 
        throw:R -> {ok, R};
        C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {reply, Reply, Command, NewState}} ->
            {reply, Reply, cmd(Command, State#state{state = NewState})};

        {ok, {reply, Reply, Command, NewState, Timeout}} ->
            {reply, Reply, cmd(Command, State#state{state = NewState}), Timeout};

        {ok, {noreply, Command, NewState}} ->
            {noreply, cmd(Command, State#state{state = NewState})};

        {ok, {noreply, Command, NewState, Timeout}} ->
            {noreply, cmd(Command, State#state{state = NewState}), Timeout};

        {ok, {stop, Reason, Reply, Command, NewState}} ->
            {stop, Reason, Reply, cmd(Command, State#state{state = NewState})};

        {ok, {stop, Reason, Command, NewState}} ->
            {stop, Reason, cmd(Command, State#state{state = NewState})};

        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)
            
    end.

handle_cast(Msg, State) ->
    Mod = State#state.mod,
    Res =
    try
        {ok, Mod:handle_cast(Msg, State#state.state)}
    catch 
        throw:R -> {ok, R};
        C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {noreply, Command, NewState}} ->
            {noreply, cmd(Command, State#state{state = NewState})};

        {ok, {noreply, Command, NewState, Timeout}} ->
            {noreply, cmd(Command, State#state{state = NewState}), Timeout};

        {ok, {stop, Reason, Command, NewState}} ->
            {stop, Reason, cmd(Command, State#state{state = NewState})};

        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)     
    end.

handle_info({tcp_closed, Socket}, State) ->
    Mod = State#state.mod,
    Socket = State#state.socket_info#socket_info.socket,
    gen_tcp:close(Socket),
    Res = 
    try
        {ok, Mod:disconnect(connection_closed, State#state.state)}
    catch 
            throw:R -> {ok, R};
            C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {ok, Command, NewState}} ->
            {noreply, cmd(Command, State#state{state = NewState})};            
        {ok, {stop, Reason, Command, NewState}} ->
            {stop, Reason, cmd(Command, State#state{state = NewState})};
        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)
    end;

handle_info(Info, State) ->
    Mod = State#state.mod,
    Res =
    try
        {ok, Mod:handle_info(Info, State#state.state)}
    catch 
        throw:R -> {ok, R};
        C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {noreply, Command, NewState}} ->
            {noreply, cmd(Command, State#state{state = NewState})};

        {ok, {noreply, Command, NewState, Timeout}} ->
            {noreply, cmd(Command, State#state{state = NewState}), Timeout};

        {ok, {stop, Reason, Command, NewState}} ->
            {stop, Reason, cmd(Command, State#state{state = NewState})};

        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)
            
    end.


terminate(Reason, State) ->
    Mod = State#state.mod,
    Socket = State#state.socket_info#socket_info.socket,
    if Socket =/= 0 ->
        gen_tcp:close(State#state.socket_info#socket_info.socket);
    true ->
        ok
    end,
    case erlang:function_exported(Mod, terminate, 2) of
	true ->
	    try
		    {ok, Mod:terminate(Reason, State#state.state)}  
        catch
		    throw:R ->
                {ok, R};
		    Class:R:Stacktrace ->
                {'EXIT', Class, R, Stacktrace}
        end;
	false ->
        {ok, ok}
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

cmd([#connect{
    ip_addr = Ip_addr,
    port = Port
    } | T], S) ->
    Mod = S#state.mod,
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.socket_opts) of
        {ok, _} ->
            S1 = S#state{socket_info = #socket_info{
                                            socket = Socket,
                                            ip_addr = Ip_addr,
                                            port = Port,
                                            connection = connect}},
            Res =             
            try
                {ok, Mod:connect(S1#state.state, S1#state.socket_info)}
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S1#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S1#state{state = NewState}),
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end;
        {error, Reason} ->
            S1 = S#state{socket_info = #socket_info{
                                            socket = 0,
                                            connection = close}},
            Res = 
            try
                {ok, Mod:disconnect(Reason, S1#state.state)}
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S1#state{state = NewState});             
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S1#state{state = NewState}),
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)

            end
    end;

cmd([#change_sock_opts{
    active = Active,
    reuseaddr = Reuseaddr, 
    nodelay = Nodelay, 
    ifaddr = Ifaddr
    } | T], S) ->
    Mod = S#state.mod,
    Socket = S#state.socket_info#socket_info.socket,
    Ip_addr = S#state.socket_info#socket_info.ip_addr,
    Port = S#state.socket_info#socket_info.port,
    if Socket =/= 0 ->
        gen_tcp:close(Socket);
        true ->
            ok
    end,
    S1 = S#state{socket_opts = [
                Ifaddr,
                binary,
                {packet, raw},
                {active, Active},
                {reuseaddr, Reuseaddr},
                {nodelay, Nodelay}
                ]},
    case {_, Sock} = gen_tcp:connect(Ip_addr, Port, S#state.socket_opts) of
        {ok, _} ->
            S2 = S1#state{socket_info = #socket_info{
                                            socket = Sock,
                                            ip_addr = Ip_addr,
                                            port = Port,
                                            connection = connect}},
            Res =             
            try
                {ok, Mod:connect(S2#state.state, S2#state.socket_info)}
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S2#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S2#state{state = NewState}),
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end;
        {error, Reason} ->
            S2 = S1#state{socket_info = #socket_info{
                                            socket = 0,
                                            connection = close}},
            Res = 
            try
                {ok, Mod:disconnect(Reason, S2#state.state)}
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S2#state{state = NewState});             
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S2#state{state = NewState}),
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)

            end
    end;

cmd([#disconnect{reason = Reason} | T], S) ->
    Mod = S#state.mod,
    Socket = S#state.socket_info#socket_info.socket,
    if Socket =/= 0 ->
        gen_tcp:close(Socket);
        true ->
            ok
    end,
    S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
    Res = 
    try
        {ok, Mod:disconnect(Reason, S1#state.state)}
    catch 
        throw:R -> {ok, R};
        C:R:S -> {'EXIT', C, R, S}
    end,
    case Res of
        {ok, {ok, Command, NewState}} ->
            cmd(Command ++ T, S1#state{state = NewState});              
        {ok, {stop, Reason, Command, NewState}} ->
            cmd(Command ++ T, S1#state{state = NewState}), 
            gen_server:stop(self(), Reason, infinity);
        {'EXIT', Class, Reason, Stacktrace} ->
            erlang:raise(Class, Reason, Stacktrace)
    end;

cmd([#read_holding_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    quantity = Quantity
    } | T], S) ->

    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 03 (чтение Holding reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} -> 
                        case Data of
                            <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, _:8, BinData/binary>> ->
                                LData = bin_to_list16(BinData, []),
                                Res =
                                try
                                    Mod:message(#read_holding_registers{
                                                                    device_number = Dev_num,
                                                                    register_number = Reg_num,
                                                                    quantity = Quantity,
                                                                    registers_value = LData
                                                                    }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
    end; 

cmd([#read_input_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    quantity = Quantity
    } | T], S) ->

    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, 1:16>>,
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 04 (чтение Input reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} -> 
                        case Data of
                            <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, _:8, BinData/binary>> ->
                                LData = bin_to_list16(BinData, []),
                                Res =
                                try
                                    Mod:message(#read_input_registers{
                                                                    device_number = Dev_num,
                                                                    register_number = Reg_num,
                                                                    quantity = Quantity,
                                                                    registers_value = LData
                                                                    }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, _Device_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
end;

cmd([#read_coils_status{
    device_number = Dev_num,
    register_number = Reg_num,
    quantity = Quantity
    } | T], S) ->

    Packet = <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 01 (чтение Coils status)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} -> 
                        case Data of
                            <<1:16, 0:16, 3:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Data/binary>> ->
                                Res =
                                try
                                    Mod:message(#read_coils_status{
                                                                    device_number = Dev_num,
                                                                    register_number = Reg_num,
                                                                    quantity = Quantity,
                                                                    registers_value = Data
                                                                    }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
    end;

cmd([#read_inputs_status{
    device_number = Dev_num,
    register_number = Reg_num,
    quantity = Quantity
    } | T], S) ->

    Packet = <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 02 (чтение Inputs status)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} -> 
                        case Data of
                            <<1:16, 0:16, 3:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Data/binary>> ->
                                Res =
                                try
                                    Mod:message(#read_inputs_status{
                                                                    device_number = Dev_num,
                                                                    register_number = Reg_num,
                                                                    quantity = Quantity,
                                                                    registers_value = Data
                                                                    }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
    end;

cmd([#write_holding_register{
    device_number = Dev_num,
    register_number = Reg_num,
    register_value = Value
    } | T], S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>,
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 06 (запись Holding reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} ->
                        case Data of 
                            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>> ->
                                Res =
                                try
                                    Mod:message(#write_holding_register{
                                                                    device_number = Dev_num,
                                                                    register_number = Reg_num,
                                                                    register_value = Value
                                                                    }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
    end;

cmd([#write_coil_status{
    device_number = Dev_num,
    register_number = Reg_num,
    register_value = Value
    } | T], S) ->
    Var = 
        case Value of
            0 -> <<0:16>>;
            1 -> <<16#FF:8, 0:8>>;
            _ -> {error, wrong_value}
        end,
    Packet = 
    if 
        Var =:= {error, wrong_value} -> 
            0;
        true ->
            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var/binary>>
    end,
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 05 (запись Coil status)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} ->
                        case Data of 
                            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var:16>> ->
                                Res =
                                try
                                    Mod:message(#write_coil_status{
                                                            device_number = Dev_num,
                                                            register_number = Reg_num,
                                                            register_value = Value
                                                            }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
    end;

cmd([#write_holding_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    registers_value = Values
    } | T], S) ->
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,
    Packet_without_values = <<1:16, 0:16, 16#0B:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    Packet = list_to_bin16(Values, Packet_without_values),
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    if Socket =/= 0 ->
        % Modbus код функции 10 (запись Holding reg)
        case gen_tcp:send(Socket, Packet) of
            ok ->
                case gen_tcp:recv(Socket, 0, 3000) of
                    {ok, Data} ->
                        case Data of 
                            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16>> ->
                                Res =
                                try
                                    Mod:message(#write_holding_registers{
                                                                    device_number = Dev_num,
                                                                    register_number = Reg_num,
                                                                    registers_value = Values
                                                                    }, S#state.state)      
                                catch 
                                    throw:R -> {ok, R};
                                    C:R:S -> {'EXIT', C, R, S}
                                end,
                                case Res of
                                    {ok, {ok, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState});              
                                    {ok, {stop, Reason, Command, NewState}} ->
                                        cmd(Command ++ T, S#state{state = NewState}), 
                                        gen_server:stop(self(), Reason, infinity);
                                    {'EXIT', Class, Reason, Stacktrace} ->
                                        erlang:raise(Class, Reason, Stacktrace)
                                end;
                            <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>> ->
                                decryption_error_code:decrypt(Err_code),
                                cmd(T, S);
                            _Else ->
                                cmd(T, S)
                        end;
                    {error, Reason} ->
                        Res = 
                        try
                            {ok, Mod:message({error, Reason}, S#state.state)} 
                        catch 
                            throw:R -> {ok, R};
                            C:R:S -> {'EXIT', C, R, S}
                        end,
                        case Res of
                            {ok, {ok, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState});              
                            {ok, {stop, Reason, Command, NewState}} ->
                                cmd(Command ++ T, S#state{state = NewState}), 
                                gen_server:stop(self(), Reason, infinity);
                            {'EXIT', Class, Reason, Stacktrace} ->
                                erlang:raise(Class, Reason, Stacktrace)
                        end
                end;
            {error, Reason} ->
                gen_tcp:close(Socket),
                S1 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
                Res = 
                try
                    {ok, Mod:disconnect(Reason, S1#state.state)}
                catch 
                    throw:R -> {ok, R};
                    C:R:S -> {'EXIT', C, R, S}
                end,
                case Res of
                    {ok, {ok, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState});              
                    {ok, {stop, Reason, Command, NewState}} ->
                        cmd(Command ++ T, S1#state{state = NewState}), 
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Stacktrace} ->
                        erlang:raise(Class, Reason, Stacktrace)
                end
        end;
        true ->
            Res = 
            try
                {ok, Mod:disconnect(socket_closed, S#state.state)}        
            catch 
                throw:R -> {ok, R};
                C:R:S -> {'EXIT', C, R, S}
            end,
            case Res of
                {ok, {ok, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState});              
                {ok, {stop, Reason, Command, NewState}} ->
                    cmd(Command ++ T, S#state{state = NewState}), 
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Stacktrace} ->
                    erlang:raise(Class, Reason, Stacktrace)
            end
    end;

cmd([], S) ->
    S.

bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);

bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).