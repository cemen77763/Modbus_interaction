%%% -----------------------------------------------------------------------------------------
%%% @doc Behaviour to interact with modbus TCP devices
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(gen_modbus).

-behaviour(gen_server).

%% API
-export([
    start_link/3,
    start_link/4,
    cast/2,
    call/2,
    call/3,
    stop/1,
    stop/3
    ]).

%% gen_server callbacks
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
    {active, true},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(state, {
    state,
    mod :: atom(),
    sock_info = #sock_info{},
    sock_opts = ?DEFAULT_SOCK_OPTS,
    buffer = <<>>,
    stage = init
    }).

-type netinfo() :: [gen_tcp:connect_option()].

%%% -----------------------------------------------------------------------------------------
%%% API
%%% -----------------------------------------------------------------------------------------

-callback init(Args :: term()) ->
    {ok, Command :: cmd(), State :: term()} | {ok, Command :: cmd(), State :: term(), timeout() | hibernate | {continue, term()}} |
    {stop, Reason :: term()} | ignore.

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

-callback connect(NetInfo :: netinfo(), State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback disconnect(Reason :: econnrefused | normal | socket_closed | shutdown | term(), State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback message(RegisterInfo :: record:record() | {error, Reason :: term()}, State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) ->
    term().

-optional_callbacks([
    terminate/2,
    handle_info/2,
    handle_continue/2
    ]).

start_link(Mod, Args, Options) ->
    gen_server:start_link(?MODULE, [Mod, Args], Options).

start_link(Name, Mod, Args, Options) ->
    gen_server:start_link(Name, ?MODULE, [Mod, Args], Options).

cast(Name, Message) ->
    gen_server:cast(Name, Message).

call(Name, Message) ->
    gen_server:call(Name, Message).

call(Name, Message, Timeout) ->
    gen_server:call(Name, Message, Timeout).

stop(Name) ->
    gen_server:stop(Name).

stop(Name, Reason, Timeout) ->
    gen_server:stop(Name, Reason, Timeout).

init([Mod, Args]) ->
    Res =
    try
        Mod:init(Args)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {ok, Command, S} ->
            case cmd(Command, #state{stage = init, mod = Mod, state = S}) of
                {stop, _S2} ->
                    {stop, shutdown};
                S2 ->
                    {ok, S2}
            end;
        {ok, Command, S, Timeout} ->
            case cmd(Command, #state{stage = init, mod = Mod, state = S}) of
                {stop, _S2} ->
                    {stop, shutdown};
                S2 ->
                    {ok, S2, Timeout}
            end;
        {stop, Reason} ->
            {stop, Reason};
        ignore ->
            ignore;
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

handle_continue(Info, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:handle_continue(Info, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {noreply, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Command, S2} ->
            {stop, S3} = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, S3};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

handle_call(Request, From, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:handle_call(Request, From, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {reply, Reply, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {reply, Reply, S3}
            end;
        {reply, Reply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {reply, Reply, S3, Timeout}
            end;
        {noreply, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Reply, Command, S2} ->
            {stop, S3} = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, Reply, S3};
        {stop, Reason, Command, S2} ->
            {stop, S3} = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, S3};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

handle_cast(Msg, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:handle_cast(Msg, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {noreply, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Command, S2} ->
            {stop, S3} = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, S3};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

msg_resp(Res, S) ->
    case Res of
        {ok, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3}
            end;
        {stop, Reason, Command, S2} ->
            {stop, S3} = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, S3}
    end.

handle_info({tcp_closed, _Socket}, S) ->
    Mod = S#state.mod,
    gen_tcp:close(S#state.sock_info#sock_info.socket),
    Res =
    try
        Mod:disconnect(connection_closed, S#state.state)
    catch
            throw:R -> {ok, R};
            C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stage = disconnect, buffer = <<>>});

handle_info({tcp, _Socket, Data}, S) ->
    parser(Data, S);

handle_info(Info, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:handle_info(Info, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {noreply, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, S3} ->
                    {stop, shutdown, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Command, S2} ->
            S3 = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, S3};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

terminate(Reason, S) ->
    Mod = S#state.mod,
    Socket = S#state.sock_info#sock_info.socket,
    case Socket of
        undefined -> ok;
        _ -> gen_tcp:close(S#state.sock_info#sock_info.socket)
    end,
    S2 =
    case Mod:disconnect(shutdown, S#state.state) of
        {ok, Command, State} ->
            cmd(Command, S#state{state = State});
        {stop, Reason, Command, State} ->
            cmd(Command, S#state{state = State})
    end,
    case erlang:function_exported(Mod, terminate, 2) of
        true ->
            try
                Mod:terminate(Reason, S2#state.state)
            catch
                throw:R ->
                    {ok, R};
                C:R:Stacktrace ->
                    {'EXIT', C, R, Stacktrace}
            end;
        false ->
            ok
    end.

code_change(_OldVsn, S, _Extra) ->
    {ok, S}.

cmd([#connect{} | T], #state{stage = connect} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{sock_info = #sock_info{socket = undefined}, stage = stop} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});
cmd([#connect{} | T], #state{stage = stop} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{stage = _} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});

cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = connect} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#state.sock_info#sock_info.socket, S2#state.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{sock_info = #sock_info{socket = undefined}, stage = stop} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = stop} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#state.sock_info#sock_info.socket, S2#state.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = _} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);

cmd([#disconnect{reason = Reason} | T], #state{stage = connect} = S) ->
    Socket = S#state.sock_info#sock_info.socket,
    gen_tcp:close(Socket),
    S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
    cmd_disconnect(S2#state.mod, Reason, T, S2#state{buffer = <<>>});
cmd([#disconnect{} | T], #state{sock_info = #sock_info{socket = undefined}, stage = stop} = S) ->
    cmd(T, S);
cmd([#disconnect{reason = Reason} | T], #state{stage = stop} = S) ->
    Socket = S#state.sock_info#sock_info.socket,
    gen_tcp:close(Socket),
    S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
    cmd_disconnect(S2#state.mod, Reason, T, S2#state{buffer = <<>>});
cmd([#disconnect{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#read_register{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_register{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#read_register{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#read_register{transaction_id = Id, type = holding, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_hregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{transaction_id = Id, type = holding, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_hregs(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_register{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_iregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_iregs(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#read_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#read_status{transaction_id = Id, type = coil, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_coils(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{transaction_id = Id, type = coil, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_coils(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_status{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_inputs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_inputs(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#write_holding_register{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_holding_register{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_holding_register{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = stop} = S) ->
    write_hreg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = connect} = S) ->
    write_hreg(T, {Id, DevNum, RegNum, Value}, S);

cmd([#write_holding_registers{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_holding_registers{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_holding_registers{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum, registers_value = Values} | T], #state{stage = stop} = S) ->
    write_hregs(T, {Id, DevNum, RegNum, Values}, S);
cmd([#write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_hregs(T, {Id, DevNum, RegNum, Values}, S);

cmd([#write_coil_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_coil_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_coil_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = stop} = S) ->
    write_creg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = connect} = S) ->
    write_creg(T, {Id, DevNum, RegNum, Value}, S);

cmd([#write_coils_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_coils_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_coils_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{buffer = <<>>});
cmd([#write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity, registers_value = Values} | T], #state{stage = stop} = S) ->
    write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S);
cmd([#write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S);

cmd([], #state{stage = stop} = S) ->
    {stop, S};
cmd([], S) ->
    S.

cmd_disconnect(Mod, Reason, T, #state{stage = stop} = S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:disconnect(Reason, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {ok, Command, S2} ->
            cmd(Command ++ T, S#state{state = S2, stage = stop});
        {stop, _Reason, Command, S2} ->
            cmd(Command ++ T, S#state{state = S2, stage = stop});
        {'EXIT', Class, Reason2, Strace} ->
            erlang:raise(Class, Reason2, Strace)
    end;
cmd_disconnect(Mod, Reason, T, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:disconnect(Reason, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {ok, Command, S2} ->
            cmd(Command ++ T, S#state{state = S2, stage = disconnect});
        {stop, _Reason, Command, S2} ->
            cmd(Command ++ T, S#state{state = S2, stage = stop});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

cmd_connect(T, #state{stage = stop} = S, {Ip_addr, Port}) ->
    Mod = S#state.mod,
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.sock_opts) of
        {ok, _} ->
            S2 = S#state{sock_info = #sock_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port,
                connection = open}},
            Res =
            try
                Mod:connect(S2#state.sock_info, S2#state.state)
            catch
                throw:R -> {ok, R};
                C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
            end,
            case Res of
                {ok, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = stop});
                {stop, _Reason, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = stop});
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            S2 = S#state{stage = stop, sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end;
cmd_connect(T, S, {Ip_addr, Port}) ->
    Mod = S#state.mod,
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.sock_opts) of
        {ok, _} ->
            S2 = S#state{sock_info = #sock_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port,
                connection = open}},
            Res =
            try
                Mod:connect(S2#state.sock_info, S2#state.state)
            catch
                throw:R -> {ok, R};
                C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
            end,
            case Res of
                {ok, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = connect});
                {stop, _Reason, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = stop});
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

read_hregs(T, {Id, DevNum, RegNum, Quantity}, S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_HREGS:8, RegNum:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

read_iregs(T, {Id, DevNum, RegNum, Quantity}, S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_IREGS:8, RegNum:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

read_coils(T, {Id, DevNum, RegNum, Quantity}, S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_COILS:8, RegNum:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

read_inputs(T, {Id, DevNum, RegNum, Quantity}, S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_INPUTS:8, RegNum:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

write_hreg(T, {Id, DevNum, RegNum, Value}, S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

write_hregs(T, {Id, DevNum, RegNum, Values}, S) ->
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,
    Mbap_len = (7 + Len),
    Packet_without_values = <<Id:16, 0:16, Mbap_len:16, DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, Reg_quantity:16, Len:8>>,
    Packet = list_to_bin16(Values, Packet_without_values),
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

write_creg(T, {Id, DevNum, RegNum, Value}, S) ->
    Var =
    case Value of
        0 -> <<0:16>>;
        1 -> <<16#FF:8, 0:8>>;
        _ -> {error, wrong_value}
    end,
    Packet =
    if Var =:= {error, wrong_value} ->
            0;
        true ->
            <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, Var/binary>>
    end,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S) ->
    Packet = <<Id:16, 0:16, 8:16, DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16, 1:8, Values:8>>,
    Socket = S#state.sock_info#sock_info.socket,
    send_message(Socket, Packet, T, S).

send_message(Socket, Packet, T, S) ->
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

change_sopts(Opts, S) when is_list(Opts) ->
    SocketOpts = lists:filter(fun(X) -> X =/= undefined end, Opts),
    S#state{sock_opts = SocketOpts};
change_sopts(_Opts, S)->
    S#state{sock_opts = ?DEFAULT_SOCK_OPTS}.

parser(Chunk, #state{buffer = Buffer} = S) ->
    parse_(<<Buffer/binary, Chunk/binary>>, {ok, [], S#state.state}, S).

parse_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, _Res, S) ->
    parse_function_(Id, Payload, S#state{buffer = Tail});
parse_(Buffer, Res, S) ->
    msg_resp(Res, S#state{buffer = Buffer}).

parse_function_(Id, <<DevNum:8, ?FUN_CODE_READ_HREGS:8, Len:8, BinData:Len/binary>>, S) ->
    LData = bin_to_list16(BinData, []),
    Msg = #read_register{type = holding, transaction_id = Id, device_number = DevNum, registers_value = LData},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_READ_IREGS:8, Len:8, BinData:Len/binary>>, S) ->
    LData = bin_to_list16(BinData, []),
    Msg = #read_register{type = input, transaction_id = Id, device_number = DevNum, registers_value = LData},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_READ_COILS:8, Len:8, BinData:Len/binary>>, S) ->
    Msg = #read_status{type = coil, transaction_id = Id, device_number = DevNum, registers_value = <<BinData:Len/binary>>},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_READ_INPUTS:8, Len:8, BinData:Len/binary>>, S) ->
    Msg = #read_status{type = input, transaction_id = Id, device_number = DevNum, registers_value = <<BinData:Len/binary>>},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>, S) ->
    Msg = #write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, _:16>>, S) ->
    Msg = #write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, Var:16>>, S) ->
    Value =
    case <<Var:16>> of
        <<0:16>> -> 0;
        <<16#FF:8, 0:8>> -> 1
    end,
    Msg = #write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16>>, S) ->
    Msg = #write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);

parse_function_(Id, <<DevNum:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>>, S) ->
    Msg = #read_register{transaction_id = Id, type = input, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>>, S) ->
    Msg = #read_register{transaction_id = Id, type = holding, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_READ_COILS:8, Err_code:8>>, S) ->
    Msg = #read_status{transaction_id = Id, type = coil, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>>, S) ->
    Msg = #read_status{transaction_id = Id, type = input, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>>, S) ->
    Msg = #write_holding_register{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>>, S) ->
    Msg = #write_holding_registers{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>>, S) ->
    Msg = #write_coil_status{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S);
parse_function_(Id, <<DevNum:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>>, S) ->
    Msg = #write_coils_status{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    Res = message(Msg, S),
    parse_(S#state.buffer, Res, S).

message(RegFun, S) ->
    Mod = S#state.mod,
    try
        Mod:message(RegFun, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> erlang:raise(C, R, Stacktrace)
    end.

bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);
bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

list_to_bin16([], Acc) ->
    Acc;
list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).