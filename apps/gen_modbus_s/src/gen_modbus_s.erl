%%% ---------------------------------------------------------------------------
%%% @doc Slave modbus TCP device behaviour
%%% @enddoc
%%% ---------------------------------------------------------------------------
-module(gen_modbus_s).

-behaviour(gen_server).

-include("gen_modbus_s.hrl").

-define(DEFAULT_PORT, 502).

-define(DEFAULT_DEVICE_NUM, 1).

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

%% Gen server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3,
    wait_connect/2
    ]).

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, true},
    {packet, raw},
    {reuseaddr, false},
    {nodelay, true}
    ]).

-record(s, {
    state :: term(),
    stage :: init | disconnect | connect | {stop, term()},
    mod :: atom(),
    device :: integer(),
    listen_sock :: gen_tcp:socket(),
    buff :: maps:map()
    }).

%%% ---------------------------------------------------------------------------
%%% @doc
%%%   The work flow (of the modbus slave) can be described as follows:
%%%
%%%   User module                          Generic
%%%   -----------                          -------
%%%     start_link       ----->             start_link
%%%     init             <-----              .
%%%     Command          ----->              .
%%%
%%%     message          <-----              .
%%%     Command          ----->              .
%%%
%%%     connect          <-----              .
%%%     Command          ----->              .
%%%
%%%     disconnect       <-----              .
%%%     Command          ----->              .
%%%
%%%     handle_call      <-----              .
%%%                      ----->             reply
%%%     Command          ----->              .
%%%
%%%     handle_cast      <-----              .
%%%     Command          ----->              .
%%%
%%%     handle_info      <-----              .
%%%     Command          ----->              .
%%%
%%%     terminate        <-----              .
%%%     Command          ----->              .
%%%
%%%                      ----->             reply
%%%@enddoc
%%% ---------------------------------------------------------------------------
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

-callback connect(Socket :: gen_tcp:socket() | undefined, State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback disconnect(Socket :: gen_tcp:socket() | undefined | all, Reason :: econnrefused | normal | socket_closed | shutdown | term(), State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback message(RegisterInfo :: reg_info(), Socket :: gen_tcp:socket(), State :: term()) ->
    {ok, Command :: cmd(), NewState :: term()} |
    {stop, Reason :: term(), Command :: cmd(), NewState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) ->
    term().

-optional_callbacks([terminate/2]).

%% ----------------------------------------------------------------------------
%% @doc start a gen slave.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec start_link(Module::atom(), [Args::term()], [Options::gen_server:options()]) ->
    {ok, Pid::pid()} | ignore | {error, Reason::term()}.
start_link(Mod, Args, Options) ->
    gen_server:start_link(?MODULE, [Mod, Args], Options).

-spec start_link({global | local, Name::atom()}, Module::atom(), [Args::term()], [Options::gen_server:options()]) ->
    {ok, Pid::pid()} | ignore | {error, Reason::term()}.
start_link(Name, Mod, Args, Options) ->
    gen_server:start_link(Name, ?MODULE, [Mod, Args], Options).

%% ----------------------------------------------------------------------------
%% @doc make a cast to gen slave.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec cast(Name::gen_server:name(), Message::term()) -> ok.
cast(Name, Message) ->
    gen_server:cast(Name, Message).

%% ----------------------------------------------------------------------------
%% @doc make a call to gen slave.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec call(Name::gen_server:name(), Message::term()) -> Reply::term().
call(Name, Message) ->
    gen_server:call(Name, Message).

-spec call(Name::gen_server:name(), Message::term(), Timeout::timeout:timer()) -> Reply::term().
call(Name, Message, Timeout) ->
    gen_server:call(Name, Message, Timeout).

%% ----------------------------------------------------------------------------
%% @doc stop a gen slave.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec stop(Name::gen_server:name()) -> ok.
stop(Name) ->
    gen_server:stop(Name).

-spec stop(Name::gen_server:name(), Reason::term(), Timeout::timeout:timer()) -> ok.
stop(Name, Reason, Timeout) ->
    gen_server:stop(Name, Reason, Timeout).

%% ----------------------------------------------------------------------------
%% @doc init callback invokes when gen_slave started.
%% @enddoc
%% ----------------------------------------------------------------------------
init([Mod, [_Port, _DevNum | Args]] = A) ->
    Res =
    try
        Mod:init(Args)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    init_it(Res, A).

init_it({ok, Command, SS}, [Mod, [Port, DevNum | _Args]]) ->
    case gen_tcp:listen(Port, ?DEFAULT_SOCK_OPTS) of
        {error, Reason} ->
            error_logger:error_msg("Gen slave can't open listen socket"),
            {stop, {listen_socket, Reason}};
        {ok, LSock} ->
            case cmd(Command, #s{state = SS, stage = init, mod = Mod, device = DevNum, listen_sock = LSock, buff = maps:new()}) of
                {stop, Reason, _S} ->
                    {stop, Reason};
                S ->
                    {ok, S}
            end
    end;
init_it({ok, Command, SS, Timeout}, [Mod, [Port, DevNum | _Args]]) ->
    case gen_tcp:listen(Port, ?DEFAULT_SOCK_OPTS) of
        {error, Reason} ->
            error_logger:error_msg("Gen slave can't open listen socket"),
            {stop, {listen_socket, Reason}};
        {ok, LSock} ->
            case cmd(Command, #s{state = SS, stage = init, mod = Mod, device = DevNum, listen_sock = LSock, buff = maps:new()}) of
                {stop, Reason, _S} ->
                    {stop, Reason};
                S ->
                    {ok, S, Timeout}
            end
    end;
init_it({stop, Reason}, _A) ->
    error_logger:error_msg("Gen slave stopped"),
    {stop, Reason};
init_it(ignore, _A) ->
    ignore;
init_it({'EXIT', Class, Reason, Strace}, _A) ->
    erlang:raise(Class, Reason, Strace).

%% ----------------------------------------------------------------------------
%% @doc handle_continue gen_server callback.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_continue(Info, S) ->
    Mod = S#s.mod,
    Res =
    try
        Mod:handle_continue(Info, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    handle_it(Res, S).

handle_it({noreply, Command, SS}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {noreply, S2}
    end;
handle_it({noreply, Command, SS, Timeout}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {noreply, S2, Timeout}
    end;
handle_it({stop, Reason, Command, SS}, S) ->
    cmd(Command, S#s{stage = {stop, Reason}, state = SS});
handle_it({'EXIT', Class, Reason, Strace}, _S) ->
    erlang:raise(Class, Reason, Strace).

%% ----------------------------------------------------------------------------
%% @doc handle_call callback invokes when somebody call gen_slave
%% working synchronous.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_call(Request, From, S) ->
    Mod = S#s.mod,
    Res =
    try
        Mod:handle_call(Request, From, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    handle_call_it(Res, S).

handle_call_it({reply, Reply, Command, SS}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {reply, Reply, S2}
    end;
handle_call_it({reply, Reply, Command, SS, Timeout}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {reply, Reply, S2, Timeout}
    end;
handle_call_it({noreply, Command, SS}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {noreply, S2}
    end;
handle_call_it({noreply, Command, SS, Timeout}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {noreply, S2, Timeout}
    end;
handle_call_it({stop, Reason, Reply, Command, SS}, S) ->
    {stop, Reason, S2} = cmd(Command, S#s{stage = {stop, Reason}, state = SS}),
    {stop, Reason, Reply, S2};
handle_call_it({stop, Reason, Command, SS}, S) ->
    cmd(Command, S#s{stage = {stop, Reason}, state = SS});
handle_call_it({'EXIT', Class, Reason, Strace}, _S) ->
    erlang:raise(Class, Reason, Strace).

%% ----------------------------------------------------------------------------
%% @doc connect callback invokes when master device connected.
%% @enddoc
%% ----------------------------------------------------------------------------
connect({ok, Command, SS}, #s{stage = {stop, Reason}} = S) -> cmd(Command, S#s{state = SS, stage = {stop, Reason}});
connect({ok, Command, SS}, S) -> cmd(Command, S#s{state = SS, stage = connect});
connect({stop, Reason, Command, SS}, #s{stage = {stop, _Reason}} = S) -> cmd(Command, S#s{state = SS, stage = {stop, Reason}});
connect({stop, Reason, Command, SS}, S) -> cmd(Command, S#s{state = SS, stage = {stop, Reason}}).

connect_it(S, Sock) ->
    Mod = S#s.mod,
    try
        Mod:connect(Sock, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

%% ----------------------------------------------------------------------------
%% @doc cast {connect, Socket} when connection fine and
%% {connect_error, Reason} when active socket error.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_cast({connect, Sock}, #s{buff = Buff} = S) ->
    S2 = connect(connect_it(S, Sock), S#s{buff = maps:put(Sock, <<>>, Buff)}),
    {noreply, S2};

handle_cast({connect_error, Reason}, S) ->
    Res = disconnect_it(undefined, Reason, S),
    resp_it(Res, check_connections(S));

%% ----------------------------------------------------------------------------
%% @doc handle_cast callback insvokes when somebody cast gen_slave.
%% working asynchronous.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_cast(Msg, S) ->
    Mod = S#s.mod,
    Res =
    try
        Mod:handle_cast(Msg, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    handle_it(Res, S).

%% ----------------------------------------------------------------------------
%% @doc parse request from modbus TCP master device then send response.
%% @enddoc
%% ----------------------------------------------------------------------------
parser(Chunk, Sock, #s{buff = Buff} = S) ->
    H = maps:get(Sock, Buff),
    parser_(<<H/binary, Chunk/binary>>, [{ok, [], S#s.state}], Sock, S).

parser_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, Res, Sock, #s{buff = Buff} = S) ->
    parser__(Id, Payload, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});
parser_(<<_:16, _Other:16, _/binary>>, Res, Sock, S) ->
    parser_(<<>>, Res, Sock, S);
parser_(Data, Res, Sock, #s{buff = Buff} = S) ->
    message_(lists:reverse(Res), {ok, [], S}, S#s{buff = maps:update(Sock, Data, Buff)}).

parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16>>,
    message(Id, #write_coil{reg_num = RegNum, val = 0, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16>>,
    message(Id, #write_coil{reg_num = RegNum, val = 1, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16, 1:8, Values:8, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16>>,
    message(Id, #write_coils{reg_num = RegNum, quantity = Quantity, val = Values, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});
parser__(Id, <<DevNum:8, ?FUN_CODE_READ_COILS:8, RegNum:16, _Quantity:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 4:16, DevNum:8, ?FUN_CODE_READ_COILS:8, 1:8>>,
    message(Id, #read_coils{reg_num = RegNum, val = undefined, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});

parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>,
    message(Id, #write_hreg{reg_num = RegNum, val = Value, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, Quantity:16, Len:8, Values:Len/binary, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, Quantity:16>>,
    message(Id, #write_hregs{reg_num = RegNum, val = Values, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});
parser__(Id, <<DevNum:8, ?FUN_CODE_READ_HREGS:8, RegNum:16, Quantity:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Len = Quantity * 2,
    MsgLen = 3 + Len,
    Resp = <<Id:16, 0:16, MsgLen:16, DevNum:8, ?FUN_CODE_READ_HREGS:8, Len:8>>,
    message(Id, #read_hregs{reg_num = RegNum, val = undefined, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});

parser__(Id, <<DevNum:8, ?FUN_CODE_READ_IREGS:8, RegNum:16, Quantity:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Len = Quantity * 2,
    MsgLen = 3 + Len,
    Resp = <<Id:16, 0:16, MsgLen:16, DevNum:8, ?FUN_CODE_READ_IREGS:8, Len:8>>,
    message(Id, #read_iregs{reg_num = RegNum, val = undefined, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});

parser__(Id, <<DevNum:8, ?FUN_CODE_READ_INPUTS:8, RegNum:16, _Quantity:16, Tail/binary>>, Res, Sock, #s{device = DevNum, buff = Buff} = S) ->
    Resp = <<Id:16, 0:16, 4:16, DevNum:8, ?FUN_CODE_READ_INPUTS:8, 1:8>>,
    message(Id, #read_inputs{reg_num = RegNum, val = undefined, response = Resp}, Res, Sock, S#s{buff = maps:update(Sock, Tail, Buff)});

parser__(Id, <<DevNum:8, FunCode:8,  _/binary>>, Res, Sock, #s{device = DevNum} = S) ->
    message(Id, #undefined_code{response = <<Id:16, 0:16, 1:16, DevNum:8, FunCode:8>>}, Res, Sock, S);
parser__(_Id, _Buff, Res, Sock, S) ->
    parser_(<<>>, Res, Sock, S).

%% ----------------------------------------------------------------------------
%% @doc message callback invokes when coils registers was changed or readed.
%% @enddoc
%% ----------------------------------------------------------------------------
message(Id, Info, Res, Sock, S) ->
    Res2 = cmd_message_it(Info, Sock, S),
    parser__(Id, maps:get(Sock, S#s.buff), [Res2 | Res], Sock, S).

message_([], Rep, _S) ->
    Rep;
message_([H | T], _Rep, S) ->
    message_it(H, T, S).

message_it({ok, Command, SS}, T, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            message_(T, {stop, Reason, S2}, S2);
        S2 ->
            message_(T, {noreply, S2}, S2)
    end;
message_it({stop, Reason, Command, SS}, T, S) ->
    {stop, Reason2, S2} = cmd(Command, S#s{stage = {stop, Reason}, state = SS}),
    message_(T, {stop, Reason2, S2}, S2);
message_it({'EXIT', Class, Reason, Strace}, _T, _S) ->
    erlang:raise(Class, Reason, Strace).

resp_it({ok, Command, SS}, S) ->
    case cmd(Command, S#s{state = SS}) of
        {stop, Reason, S2} ->
            {stop, Reason, S2};
        S2 ->
            {noreply, S2}
    end;
resp_it({stop, Reason, Command, SS}, S) ->
    cmd(Command, S#s{stage = {stop, Reason}, state = SS});
resp_it({'EXIT', Class, Reason, Strace}, _S) ->
    erlang:raise(Class, Reason, Strace).

%% ----------------------------------------------------------------------------
%% @doc check list of connected master devices if list empty change gen_slave
%% stage to disconnect.
%% @enddoc
%% ----------------------------------------------------------------------------
check_connections(#s{buff = #{}} = S) ->
    S#s{stage = disconnect};
check_connections(S) ->
    S.

%% ----------------------------------------------------------------------------
%% @doc receive data from modbus TCP master device.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_info({tcp, Sock, Data}, S)->
    case maps:is_key(Sock, S#s.buff) of
        true ->
            parser(Data, Sock, S);
        _ ->
            {noreply, S}
    end;

%% ----------------------------------------------------------------------------
%% @doc when socket of master device closed receive {tcp_closed, Socket}
%% if socket is member close it.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_info({tcp_closed, Sock}, #s{buff = Buff} = S) ->
    case maps:take(Sock, Buff) of
        {_Val, Buff2} ->
            gen_tcp:close(Sock),
            Res = disconnect_it(Sock, connection_closed, S),
            S2 = check_connections(S),
            resp_it(Res, S2#s{buff = Buff2});
        _ ->
            {noreply, S}
    end;

%% ----------------------------------------------------------------------------
%% @doc handle_info callback invokes when gen_slave receive a message.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_info(Info, S) ->
    Mod = S#s.mod,
    Res =
    try
        Mod:handle_info(Info, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    handle_it(Res, S).

%% ----------------------------------------------------------------------------
%% @doc terminate callback invokes when gen_slave was stopped.
%% @enddoc
%% ----------------------------------------------------------------------------
terminate(Reason, S) ->
    Mod = S#s.mod,
    gen_tcp:close(S#s.listen_sock),
    case disconnect_it(all, shutdown, S) of
        {ok, Command, SS} ->
            S2 = cmd(Command, S#s{buff = maps:new(), stage = disconnect, state = SS}),
            terminate_it(Mod, Reason, S2);
        {stop, Reason2, Command, SS} ->
            {stop, Reason3, S2} = cmd(Command, S#s{buff = maps:new(), state = SS, stage = {stop, Reason2}}),
            terminate_it(Mod, Reason3, S2)
    end.

terminate_it(Mod, Reason, S) ->
    case erlang:function_exported(Mod, terminate, 2) of
        true ->
            try
                Mod:terminate(Reason, S#s.state)
            catch
                throw:R ->
                    {ok, R};
                C:R:Stacktrace ->
                    {'EXIT', C, R, Stacktrace}
            end;
        _ ->
            ok
    end.

%% ----------------------------------------------------------------------------
%% @doc gen server code change gen_server callback.
%% @enddoc
%% ----------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ----------------------------------------------------------------------------
%% @doc disconnect callback invokes when connection to the master device
%% closed.
%% @enddoc
%% ----------------------------------------------------------------------------
disconnect_it(Sock, Reason, S) ->
    Mod = S#s.mod,
    try
        Mod:disconnect(Sock, Reason, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

%% ----------------------------------------------------------------------------
%% @doc commands for interaction with gen_slave module from callbacks return
%% wait_connect => waiting for connection with master device;
%% disconnect (Socket, Reason) => disconnected from Socket;
%% response (Socket, Response) => send response to the master request;
%% error_response (ErrorCode, Response, Socket) => send error response with
%% error code;
%% {stop, Reason} => stop gen_slave device.
%% @enddoc
%% ----------------------------------------------------------------------------
cmd([#wait_connect{} | T], S) ->
    spawn_link(gen_modbus_s, wait_connect, [self(), S#s.listen_sock]),
    cmd(T, S);

cmd([#disconnect{socket = Sock, reason = Reason} | T], #s{stage = connect, buff = Buff} = S) ->
    gen_tcp:close(Sock),
    S2 = check_connections(S),
    cmd_disconnect(T, Sock, Reason, S2#s{buff = maps:remove(Sock, Buff)});
cmd([#disconnect{} | T], #s{buff = #{}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#disconnect{socket = Sock, reason = Reason} | T], #s{stage = {stop, _Reason}, buff = Buff} = S) ->
    gen_tcp:close(Sock),
    S2 = check_connections(S),
    cmd_disconnect(T, Sock, Reason, S2#s{buff = maps:remove(Sock, Buff)});
cmd([#disconnect{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#response{socket = Sock, response = Resp} | T], #s{buff = Buff} = S) ->
    case gen_tcp:send(Sock, Resp) of
        {error, Reason} ->
            gen_tcp:close(Sock),
            S2 = check_connections(S),
            cmd_disconnect(T, Sock, Reason, S2#s{buff = maps:remove(Sock, Buff)});
        _ ->
            cmd(T, S)
    end;

cmd([#error_response{error_code = ErrCode, response = <<Id:16, 0:16, _:16, DevNum:8, ChangeFunCode:4, FunCode:4, _/binary>>, socket = Sock} | T], #s{buff = Buff} = S) ->
    Err = ChangeFunCode bor 8,
    case gen_tcp:send(Sock, <<Id:16, 0:16, 3:16, DevNum:8, Err:4, FunCode:4, ErrCode:8>>) of
        {error, Reason} ->
            gen_tcp:close(Sock),
            S2 = check_connections(S),
            cmd_disconnect(T, Sock, Reason, S2#s{buff = maps:remove(Sock, Buff)});
        _ ->
            cmd(T, S)
    end;

cmd([#stop{reason = Reason} | T], S) ->
    cmd(T, S#s{stage = {stop, Reason}});

cmd([], #s{stage = {stop, Reason}} = S) ->
    {stop, Reason, S};
cmd([], S) ->
    S.

%% ----------------------------------------------------------------------------
%% @doc waiting connect then send socket to gen_slave or send error.
%% @enddoc
%% ----------------------------------------------------------------------------
wait_connect(From, LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, Sock} ->
            gen_tcp:controlling_process(Sock, From),
            gen_server:cast(From, {connect, Sock});
        {error, Reason} ->
            gen_server:cast(From, {connect_error, Reason})
    end.

%% ----------------------------------------------------------------------------
%% @doc disconnect from modbus TCP master device.
%% @enddoc
%% ----------------------------------------------------------------------------
cmd_disconnect(T, Sock, Reason, S) ->
    Res = disconnect_it(Sock, Reason, S),
    cmd_disconnect_(Res, T, S).

cmd_disconnect_({ok, Command, SS}, T, #s{stage = {stop, Reason}} = S) ->
    cmd(Command ++ T, S#s{state = SS, stage = {stop, Reason}});
cmd_disconnect_({ok, Command, SS}, T, S) ->
    cmd(Command ++ T, S#s{state = SS});
cmd_disconnect_({stop, Reason, Command, SS}, T, S) ->
    cmd(Command ++ T, S#s{state = SS, stage = {stop, Reason}});
cmd_disconnect_({'EXIT', Class, Reason2, Strace}, _T, _S) ->
    erlang:raise(Class, Reason2, Strace).

%% ----------------------------------------------------------------------------
%% @doc message callback invokes when coils registers was changed or readed.
%% @enddoc
%% ----------------------------------------------------------------------------
cmd_message_it(Info, Sock, S) ->
    Mod = S#s.mod,
    try
        Mod:message(Info, Sock, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> erlang:raise(C, R, Stacktrace)
    end.
