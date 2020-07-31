%%% -----------------------------------------------------------------------------------------
%%% @doc Slave modbus TCP device behaviour
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(gen_slave).

-behaviour(gen_server).

-include("../include/gen_modbus.hrl").
-include("../include/gen_slave.hrl").

%% API
-export([
    start_link/3,
    start_link/4,
    cast/2,
    call/2,
    call/3,
    stop/1,
    stop/3,
    wait_connect/2
    ]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3
    ]).

-define(DEFAULT_DEVICE_NUM, 2).

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
    stage :: atom(),
    mod :: atom(),
    listen_sock :: gen_tcp:socket(),
    active_socks :: [gen_tcp:socket()],
    coils = <<0>>,
    holding :: dict:dict(),
    buff = <<>>
    }).

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

-callback connect(Socket :: gen_tcp:socket(), State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback disconnect(Socket :: gen_tcp:socket(), Reason :: econnrefused | normal | socket_closed | shutdown | term(), State :: term()) ->
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
    case gen_tcp:listen(5000, ?DEFAULT_SOCK_OPTS) of
        {ok, LSock} ->
            init_it([Mod, Args], LSock);
        {error, Reason} ->
            {stop, Reason}
    end.

init_it([Mod, Args], LSock) ->
    Res =
    try
        Mod:init(Args)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {ok, Command, SS} ->
            case cmd(Command, #state{state = SS, stage = init, mod = Mod, listen_sock = LSock, holding = dict:new()}) of
                {stop, Reason, _S} ->
                    {stop, Reason};
                S ->
                    {ok, S}
            end;
        {ok, Command, SS, Timeout} ->
            case cmd(Command, #state{state = SS, stage = init, mod = Mod, listen_sock = LSock, holding = dict:new()}) of
                {stop, Reason, _S2} ->
                    {stop, Reason};
                S ->
                    {ok, S, Timeout}
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
        {noreply, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2}
            end;
        {noreply, Command, SS, Timeout} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2, Timeout}
            end;
        {stop, Reason, Command, SS} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = SS});
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
        {reply, Reply, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {reply, Reply, S2}
            end;
        {reply, Reply, Command, SS, Timeout} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {reply, Reply, S2, Timeout}
            end;
        {noreply, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2}
            end;
        {noreply, Command, SS, Timeout} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2, Timeout}
            end;
        {stop, Reason, Reply, Command, SS} ->
            {stop, Reason, S2} = cmd(Command, S#state{stage = {stop, Reason}, state = SS}),
            {stop, Reason, Reply, S2};
        {stop, Reason, Command, SS} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = SS});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

connect_it(S) ->
    Mod = S#state.mod,
    try
        Mod:connect(S#state.listen_sock, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

connect({ok, Command, SS}, #state{stage = {stop, Reason}} = S) -> cmd(Command, S#state{state = SS, stage = {stop, Reason}});
connect({ok, Command, SS}, S) -> cmd(Command, S#state{state = SS, stage = connect});
connect({stop, Reason, Command, SS}, #state{stage = {stop, _Reason}} = S) -> cmd(Command, S#state{state = SS, stage = {stop, Reason}});
connect({stop, Reason, Command, SS}, S) -> cmd(Command, S#state{state = SS, stage = {stop, Reason}}).


handle_cast({connect, Sock}, S) ->
    S2 = connect(connect_it(S), S#state{active_socks = [Sock]}),
    {noreply, S2};

handle_cast({connect, error, Reason}, S) ->
    Res = disconnect_it(S#state.active_socks, Reason, S),
    msg_resp(Res, S#state{stage = disconnect, buff = <<>>, active_socks = [undefined]});

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
        {noreply, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2}
            end;
        {noreply, Command, SS, Timeout} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2, Timeout}
            end;
        {stop, Reason, Command, SS} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = SS});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

parser(Chunk, #state{buff = Buff} = S) ->
    parser_(<<Buff/binary, Chunk/binary>>, [{ok, [], S#state.state}], S).

parser_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, Res, S) ->
    parser__(Id, Payload, Res, S#state{buff = Tail});

parser_(Buff, Res, S) ->
    message_(Res, {ok, [], S}, S#state{buff = Buff}).

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    Holding = dict:store(RegNum, Value, S#state.holding),
    gen_tcp:send(Sock, <<Id:16, 0:16, 6:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>),
    message(Id, {writed, holding, RegNum}, Res, S#state{buff = Tail, holding = Holding});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, _RegQuantity:16, Len:8, Values:Len/binary, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    Quantity = Len div 2,
    Holding = store_hregs(Values, RegNum, S#state.holding),
    gen_tcp:send(Sock, <<Id:16, 0:16, 6:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, Quantity:16>>),
    message(Id, {writed, holding, RegNum}, Res, S#state{buff = Tail, holding = Holding});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    S2 = change_coil(RegNum, off, S),
    gen_tcp:send(Sock, <<Id:16, 0:16, 6:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16>>),
    message(Id, {alarm, on, RegNum}, Res, S2#state{buff = Tail});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    S2 = change_coil(RegNum, on, S),
    gen_tcp:send(Sock, <<Id:16, 0:16, 6:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16>>),
    message(Id, {alarm, on, RegNum}, Res, S2#state{buff = Tail});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16, 1:8, Values:8, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    <<Coil>> = S#state.coils,
    Coils = Values bor Coil,
    gen_tcp:send(Sock, <<Id:16, 0:16, 6:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16>>),
    message(Id, {alarm, on, RegNum}, Res, S#state{buff = Tail, coils = <<Coils>>});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_READ_HREGS:8, RegNum:16, Quantity:16, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    Len = Quantity * 2,
    MsgLen = Len + 3,
    BinData = find_hregs(S#state.holding, RegNum, Quantity, <<>>),
    gen_tcp:send(Sock, <<Id:16, 0:16, MsgLen:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_READ_HREGS:8, Len:8, BinData:Len/binary>>),
    message(Id, {readed, holding, RegNum}, Res, S#state{buff = Tail});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_READ_COILS:8, RegNum:16, _Quantity:16, Tail/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    <<Values>> = S#state.coils,
    gen_tcp:send(Sock, <<Id:16, 0:16, 4:16, ?DEFAULT_DEVICE_NUM:8, ?FUN_CODE_READ_COILS:8, 1:8, Values:8>>),
    message(Id, {readed, coils, RegNum}, Res, S#state{buff = Tail});

parser__(Id, <<?DEFAULT_DEVICE_NUM:8, _:4, T:4, _/binary>>, Res, #state{active_socks = [Sock]} = S) ->
    gen_tcp:send(Sock, <<Id:16, 0:16, 3:16, ?DEFAULT_DEVICE_NUM:8, 8:4, T:4, 2:8>>),
    parser_(S#state.buff, Res, S);

parser__(_Id, <<_DevNum:8, _/binary>>, Res, S) ->
    parser_(S#state.buff, Res, S);

parser__(Id, Buff, Res, #state{buff = Tail} = S) ->
    io:format("Id is ~w payload is ~w~n", [Id, Buff]),
    parser_(<<Buff/binary, Tail/binary>>, Res, S).

message(Id, Info, Res, S) ->
    Mod = S#state.mod,
    Res2 =
    try
        Mod:message(Info, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> erlang:raise(C, R, Stacktrace)
    end,
    parser__(Id, S#state.buff, [Res2 | Res], S).

message_([], Rep, _S) ->
    Rep;
message_([H | T], _Rep, S) ->
    case H of
        {ok, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    message_(T, {stop, Reason, S2}, S2);
                S2 ->
                    message_(T, {noreply, S2}, S2)
            end;
        {stop, Reason, Command, SS} ->
            {stop, Reason2, S2} = cmd(Command, S#state{stage = {stop, Reason}, state = SS}),
            message_(T, {stop, Reason2, S2}, S2);
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

msg_resp(Res, S) ->
    case Res of
        {ok, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2}
            end;
        {stop, Reason, Command, SS} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = SS});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

handle_info({tcp, Socket, Data}, S) when [Socket] =:= S#state.active_socks ->
    parser(Data, S);

handle_info({tcp_closed, Socket}, S) when [Socket] =:= S#state.active_socks ->
    gen_tcp:close(Socket),
    Res = disconnect_it(Socket, connection_closed, S),
    msg_resp(Res, S#state{stage = disconnect, buff = <<>>, active_socks = [undefined]});

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
        {noreply, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2}
            end;
        {noreply, Command, SS, Timeout} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, Reason, S2} ->
                    {stop, Reason, S2};
                S2 ->
                    {noreply, S2, Timeout}
            end;
        {stop, Reason, Command, SS} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = SS});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

terminate(Reason, S) ->
    Mod = S#state.mod,
    gen_tcp:close(S#state.listen_sock),
    case disconnect_it(S#state.active_socks, shutdown, S) of
        {ok, Command, SS} ->
            S2 = cmd(Command, S#state{active_socks = [], buff = <<>>, stage = disconnect, state = SS}),
            terminate_it(Mod, Reason, S2);
        {stop, Reason2, Command, SS} ->
            {stop, Reason3, S2} = cmd(Command, S#state{buff = <<>>, state = SS, stage = {stop, Reason2}}),
            terminate_it(Mod, Reason3, S2)
    end.

terminate_it(Mod, Reason, S) ->
    case erlang:function_exported(Mod, terminate, 2) of
        true ->
            try
                Mod:terminate(Reason, S#state.state)
            catch
                throw:R ->
                    {ok, R};
                C:R:Stacktrace ->
                    {'EXIT', C, R, Stacktrace}
            end;
        false ->
            ok
    end.

disconnect_it(Socket, Reason, S) ->
    Mod = S#state.mod,
    try
        Mod:disconnect(Socket, Reason, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

code_change(_OldVsn, S, _Extra) ->
    {ok, S}.

cmd([wait_connect | T], #state{stage = init} = S) ->
    spawn(gen_slave, wait_connect, [self(), S#state.listen_sock]),
    cmd(T, S);
cmd([wait_connect | T], #state{stage = connect} = S) ->
    cmd(T, S);
cmd([wait_connect | T], #state{active_socks = undefined, stage = {stop, _Reason}} = S) ->
    spawn(gen_slave, wait_connect, [self(), S#state.listen_sock]),
    cmd(T, S);
cmd([wait_connect | T], #state{stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([wait_connect | T], #state{stage = disconnect} = S) ->
    spawn(gen_slave, wait_connect, [self(), S#state.listen_sock]),
    cmd(T, S);

cmd([#disconnect{reason = Reason} | T], #state{stage = connect} = S) ->
    [Socket] = S#state.active_socks,
    gen_tcp:close(Socket),
    S2 = S#state{buff = <<>>, active_socks = []},
    cmd_disconnect(T, Reason, S2);
cmd([#disconnect{} | T], #state{active_socks = [], stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#disconnect{reason = Reason} | T], #state{stage = {stop, _Reason}} = S) ->
    [Socket] = S#state.active_socks,
    gen_tcp:close(Socket),
    S2 = S#state{buff = <<>>, active_socks = []},
    cmd_disconnect(T, Reason, S2);
cmd([#disconnect{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#alarm{status = Status, type = Type} | T], S) ->
    S2 = cmd_message({alarm, Status, Type}, S),
    cmd(T, change_coil(Type, Status, S2));

cmd([], #state{stage = {stop, Reason}} = S) ->
    {stop, Reason, S};
cmd([], S) ->
    S.

wait_connect(From, LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, Sock} ->
            gen_tcp:controlling_process(Sock, From),
            gen_server:cast(From, {connect, Sock});
        {error, Reason} ->
            gen_server:cast(From, {connect, error, Reason})
    end.

cmd_disconnect(T, Reason, #state{stage = {stop, Reason}} = S) ->
    case disconnect_it(S#state.active_socks, Reason, S) of
        {ok, Command, SS} ->
            cmd(Command ++ T, S#state{state = SS, stage = disconnect});
        {stop, _Reason, Command, SS} ->
            cmd(Command ++ T, S#state{state = SS, stage = {stop, Reason}});
        {'EXIT', Class, Reason2, Strace} ->
            erlang:raise(Class, Reason2, Strace)
    end;
cmd_disconnect(T, Reason, #state{stage = {stop, Reason}} = S) ->
    case disconnect_it(S#state.active_socks, Reason, S) of
        {ok, Command, SS} ->
            cmd(Command ++ T, S#state{state = SS, stage = {stop, Reason}});
        {stop, _Reason, Command, SS} ->
            cmd(Command ++ T, S#state{state = SS, stage = {stop, Reason}});
        {'EXIT', Class, Reason2, Strace} ->
            erlang:raise(Class, Reason2, Strace)
    end.

cmd_message(Info, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(Info, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> erlang:raise(C, R, Stacktrace)
    end,
    case Res of
        {ok, Command, SS} ->
            case cmd(Command, S#state{state = SS}) of
                {stop, _Reason, S2} ->
                    S2;
                S2 ->
                    S2
            end;
        {stop, Reason, Command, SS} ->
            {stop, _Reason, S2} = cmd(Command, S#state{stage = {stop, Reason}, state = SS}),
            S2;
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

change_coil(RegNum, on, S) ->
    change_coil_(RegNum, 1, S);
change_coil(RegNum, off, S) ->
    change_coil_(RegNum, 0, S).

change_coil_(RegNum, Val, S) ->
    H = 8 - RegNum,
    T = 7 - H,
    <<Head:H, _:1, Tail:T>> = S#state.coils,
    S#state{coils = <<Head:H, Val:1, Tail:T>>}.

find_hregs(_Dict, _RegNum, 0, Acc) ->
    Acc;
find_hregs(Dict, RegNum, Quantity, Acc) ->
    case dict:find(RegNum, Dict) of
        {ok, Val} ->
            find_hregs(Dict, RegNum + 1, Quantity - 1, <<Acc/binary, Val:16>>);
        error ->
            0
    end.

store_hregs(<<>>, _RegNum, Dict) ->
    Dict;
store_hregs(<<Val:16, T/binary>>, RegNum, Dict) ->
    store_hregs(T, RegNum + 1, dict:store(RegNum, Val, Dict)).