%%% ---------------------------------------------------------------------------
%%% @doc Behaviour to interact with modbus TCP devices
%%% @enddoc
%%% ---------------------------------------------------------------------------
-module(gen_modbus_m).

-behaviour(gen_server).

-include("gen_modbus_m.hrl").

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

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, true},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(s, {
    state :: term(),
    mod :: atom(),
    sock_info = #sock_info{},
    sock_opts = ?DEFAULT_SOCK_OPTS,
    recv_buff = <<>>,
    send_buff = <<>>,
    stage :: init | disconnect | connect | {stop, Reason :: term()}
    }).

%%% ---------------------------------------------------------------------------
%%% @doc
%%%   The work flow (of the modbus mster) can be described as follows:
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

-callback connect(records:record(sock_info), State :: term()) ->
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

-optional_callbacks([terminate/2]).

%% ----------------------------------------------------------------------------
%% @doc start a gen master.
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
%% @doc make a cast to gen master.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec cast(Name::atom(), Message::term()) -> ok.
cast(Name, Message) ->
    gen_server:cast(Name, Message).

%% ----------------------------------------------------------------------------
%% @doc make a call to gen master.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec call(Name::atom(), Message::term()) -> Reply::term().
call(Name, Message) ->
    gen_server:call(Name, Message).

-spec call(Name::atom(), Message::term(), Timeout::timeout:timer()) -> Reply::term().
call(Name, Message, Timeout) ->
    gen_server:call(Name, Message, Timeout).

%% ----------------------------------------------------------------------------
%% @doc stop a gen master.
%% @enddoc
%% ----------------------------------------------------------------------------
-spec stop(Name::atom()) -> ok.
stop(Name) ->
    gen_server:stop(Name).

-spec stop(Name::atom(), Reason::term(), Timeout::timeout:timer()) -> ok.
stop(Name, Reason, Timeout) ->
    gen_server:stop(Name, Reason, Timeout).

%% ----------------------------------------------------------------------------
%% @doc init callback invokes when gen_master started.
%% @enddoc
%% ----------------------------------------------------------------------------
init([Mod, Args]) ->
    Res =
    try
        Mod:init(Args)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    init_it(Res, Mod).

init_it({ok, Command, SS}, Mod) ->
    case cmd(Command, #s{stage = init, mod = Mod, state = SS}) of
        {stop, Reason, _S2} ->
            {stop, Reason};
        S2 ->
            {ok, S2}
    end;
init_it({ok, Command, SS, Timeout}, Mod) ->
    case cmd(Command, #s{stage = init, mod = Mod, state = SS}) of
        {stop, Reason, _S2} ->
            {stop, Reason};
        S2 ->
            {ok, S2, Timeout}
    end;
init_it({stop, Reason}, _Mod) ->
    {stop, Reason};
init_it(ignore, _Mod) ->
    ignore;
init_it({'EXIT', Class, Reason, Strace}, _Mod) ->
    erlang:raise(Class, Reason, Strace).

%% ----------------------------------------------------------------------------
%% @doc handle_continue callback.
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
%% @doc handle_call callback invokes when somebody call gen_master
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
%% @doc handle_cast callback insvokes when somebody cast gen_master.
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
%% @doc if connection closed.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_info({tcp_closed, Socket}, S) when Socket =:= S#s.sock_info#sock_info.socket ->
    gen_tcp:close(Socket),
    Res = disconnect_it(connection_closed, S),
    resp_it(Res, S#s{stage = disconnect, send_buff = <<>>, recv_buff = <<>>, sock_info = #sock_info{socket = undefined}});

%% ----------------------------------------------------------------------------
%% @doc receive data from connected slave device.
%% @enddoc
%% ----------------------------------------------------------------------------
handle_info({tcp, Socket, Data}, S) when Socket =:= S#s.sock_info#sock_info.socket ->
    parser(Data, S);

%% ----------------------------------------------------------------------------
%% @doc handle_info callback invokes when gen_master receive message.
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
%% @doc terminate callback invokes when gen_master was stopped.
%% @enddoc
%% ----------------------------------------------------------------------------
terminate(Reason, S) ->
    Mod = S#s.mod,
    Socket = S#s.sock_info#sock_info.socket,
    Socket =/= undefined andalso
        gen_tcp:close(Socket),
    case disconnect_it(shutdown, S) of
        {ok, Command, S2} ->
            S3 = cmd(Command, S#s{sock_info = #sock_info{socket = undefined}, send_buff = <<>>, recv_buff = <<>>, stage = disconnect, state = S2}),
            terminate_it(Mod, Reason, S3);
        {stop, Reason2, Command, S2} ->
            {stop, Reason3, S3} = cmd(Command, S#s{send_buff = <<>>, recv_buff = <<>>, state = S2, stage = {stop, Reason2}, sock_info = #sock_info{socket = undefined}}),
            terminate_it(Mod, Reason3, S3)
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
%% @doc gen server code change callback.
%% @enddoc
%% ----------------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ----------------------------------------------------------------------------
%% @doc commands for interaction with gen_master module from callbacks return;
%% connect (ip_addr, port) => connect with slave device;
%% change_sock_opts (reuseaddr, nodelay, ifaddr) => change options of a socket;
%% disconnect (reason) => disconnect from slave device;
%% read input, holding registers and coil, input status;
%% write input, holding registers and coil, input status.
%% @enddoc
%% ----------------------------------------------------------------------------
cmd([#connect{} | T], #s{stage = connect} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});
cmd([#connect{} | T], #s{stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #s{stage = _} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});

cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #s{stage = connect} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#s.sock_info#sock_info.socket, S2#s.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #s{stage = {stop, _Reason}} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#s.sock_info#sock_info.socket, S2#s.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #s{stage = _} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);

cmd([#disconnect{reason = Reason} | T], #s{stage = connect} = S) ->
    cmd_disconnect(T, Reason, S);
cmd([#disconnect{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#disconnect{reason = Reason} | T], #s{stage = {stop, Reason}} = S) ->
    cmd_disconnect(T, Reason, S);
cmd([#disconnect{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#read_register{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#read_register{transaction_id = Id, type = holding, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = {stop, _Reason}} = S) ->
    read_hregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{transaction_id = Id, type = holding, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = connect} = S) ->
    read_hregs(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_register{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = {stop, _Reason}} = S) ->
    read_iregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = connect} = S) ->
    read_iregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{} | T], #s{stage = init} = S) ->
    cmd(T, S);

cmd([#read_status{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#read_status{transaction_id = Id, type = coil, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = {stop, _Reason}} = S) ->
    read_coils(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{transaction_id = Id, type = coil, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = connect} = S) ->
    read_coils(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_status{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = {stop, _Reason}} = S) ->
    read_inputs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #s{stage = connect} = S) ->
    read_inputs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#write_holding_register{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #s{stage = {stop, _Reason}} = S) ->
    write_hreg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #s{stage = connect} = S) ->
    write_hreg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_holding_register{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#write_holding_registers{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum, registers_value = Values} | T], #s{stage = {stop, _Reason}} = S) ->
    write_hregs(T, {Id, DevNum, RegNum, Values}, S);
cmd([#write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum, registers_value = Values} | T], #s{stage = connect} = S) ->
    write_hregs(T, {Id, DevNum, RegNum, Values}, S);
cmd([#write_holding_registers{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#write_coil_status{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #s{stage = {stop, _Reason}} = S) ->
    write_creg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #s{stage = connect} = S) ->
    write_creg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_coil_status{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#write_coils_status{} | T], #s{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity, registers_value = Values} | T], #s{stage = {stop, _Reason}} = S) ->
    write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S);
cmd([#write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity, registers_value = Values} | T], #s{stage = connect} = S) ->
    write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S);
cmd([#write_coils_status{} | T], #s{stage = _} = S) ->
    cmd(T, S);

cmd([#stop{reason = Reason} | T], S) ->
    cmd(T, S#s{stage = {stop, Reason}});

cmd([], #s{stage = {stop, Reason}, send_buff = <<>>} = S) ->
    {stop, Reason, S};
cmd([], #s{send_buff = <<>>} = S) ->
    S;
cmd([], #s{send_buff = Buff} = S) ->
    send_message(S#s{send_buff = count_mbap(Buff)}).

%% ----------------------------------------------------------------------------
%% @doc disconnect callback invokes when master disconnected to slave device.
%% @enddoc
%% ----------------------------------------------------------------------------
disconnect_it(Reason, S) ->
    Mod = S#s.mod,
    try
        Mod:disconnect(Reason, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

cmd_disconnect(T, Reason, S) ->
    Socket = S#s.sock_info#sock_info.socket,
    Socket =/= undefined andalso
        gen_tcp:close(Socket),
    S2 = S#s{send_buff = <<>>, recv_buff = <<>>, sock_info = #sock_info{socket = undefined}},
    Res = disconnect_it(Reason, S2),
    cmd_disconnect_(Res, T, S2).

cmd_disconnect_({ok, Command, SS}, T, #s{stage = {stop, Reason}} = S) ->
    cmd(Command ++ T, S#s{state = SS, stage = {stop, Reason}});
cmd_disconnect_({ok, Command, SS}, T, S) ->
    cmd(Command ++ T, S#s{state = SS, stage = disconnect});
cmd_disconnect_({stop, Reason, Command, SS}, T, S) ->
    cmd(Command ++ T, S#s{state = SS, stage = {stop, Reason}});
cmd_disconnect_({'EXIT', Class, Reason2, Strace}, _T, _S) ->
    erlang:raise(Class, Reason2, Strace).

%% ----------------------------------------------------------------------------
%% @doc connect callback invokes when master connected to slave device.
%% @enddoc
%% ----------------------------------------------------------------------------
connect_it(S) ->
    Mod = S#s.mod,
    try
        Mod:connect(S#s.sock_info, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

cmd_connect(T, S, {Ip_addr, Port}) ->
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#s.sock_opts) of
        {ok, _} ->
            S2 = S#s{sock_info = #sock_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port}},
            Res = connect_it(S2),
            cmd_connect_(Res, T, S2);
        {error, Reason} ->
            cmd_disconnect(T, Reason, S#s{stage = {stop, Reason}})
    end.

cmd_connect_({ok, Command, SS}, T, #s{stage = {stop, Reason}} = S) ->
    cmd(Command ++ T, S#s{state = SS, stage = {stop, Reason}});
cmd_connect_({ok, Command, SS}, T, S) ->
    cmd(Command ++ T, S#s{state = SS, stage = connect});
cmd_connect_({stop, Reason, Command, SS}, T, S) ->
    cmd(Command ++ T, S#s{state = SS, stage = {stop, Reason}});
cmd_connect_({'EXIT', Class, Reason2, Strace}, _T, _S) ->
    erlang:raise(Class, Reason2, Strace).

%% ----------------------------------------------------------------------------
%% @doc transform messages to modbus TCP protocol packet.
%% @enddoc
%% ----------------------------------------------------------------------------
read_hregs(T, {Id, DevNum, RegNum, Quantity}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_HREGS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

read_iregs(T, {Id, DevNum, RegNum, Quantity}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_IREGS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

read_coils(T, {Id, DevNum, RegNum, Quantity}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_COILS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

read_inputs(T, {Id, DevNum, RegNum, Quantity}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_INPUTS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

write_hreg(T, {Id, DevNum, RegNum, Value}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

write_hregs(T, {Id, DevNum, RegNum, Values}, #s{send_buff = Buff} = S) ->
    RegQuantity = length(Values),
    Len = RegQuantity * 2,
    Mbap_len = (7 + Len),
    PacketWithoutValues = <<Id:16, 0:16, Mbap_len:16, DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, RegQuantity:16, Len:8>>,
    Packet = list_to_bin16(Values, PacketWithoutValues),
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

write_creg(T, {Id, DevNum, RegNum, 0}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>});
write_creg(T, {Id, DevNum, RegNum, 1}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>});
write_creg(T, {_, _, _, undefined}, S) ->
    cmd(T, S).

write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, #s{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 8:16, DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16, 1:8, Values:8>>,
    cmd(T, S#s{send_buff = <<Buff/binary, Packet/binary>>}).

%% ----------------------------------------------------------------------------
%% @doc count header for multiple modbus requests.
%% @enddoc
%% ----------------------------------------------------------------------------
count_mbap(<<Id:16, 0:16, Len:16, Buff/binary>>) ->
    {MsgLen, Pdu} = count_mbap_(<<Len:16, Buff/binary>>),
    <<Id:16, 0:16, MsgLen:16, Pdu:MsgLen/binary>>.

count_mbap_(<<MsgLen:16, Pdu:MsgLen/binary, _Id:16, 0:16, Len:16, Tail/binary>>) ->
    MsgLen2 = MsgLen + Len,
    count_mbap_(<<MsgLen2:16, Pdu/binary, Tail/binary>>);
count_mbap_(<<MsgLen:16, Pdu:MsgLen/binary>>) -> {MsgLen, Pdu}.

%% ----------------------------------------------------------------------------
%% @doc send message to modbus TCP slave device.
%% @enddoc
%% ----------------------------------------------------------------------------
send_message(S) ->
    Socket = S#s.sock_info#sock_info.socket,
    Packet = S#s.send_buff,
    R = gen_tcp:send(Socket, Packet),
    send_message_(S#s{send_buff = <<>>}, R).
send_message_(#s{stage = {stop, Reason}} = S, ok) -> {stop, Reason, S};
send_message_(S, ok) -> S;
send_message_(S, {error, Reason}) -> cmd_disconnect([], Reason, S).

%% ----------------------------------------------------------------------------
%% @doc transform record with socket options to proplist.
%% @enddoc
%% ----------------------------------------------------------------------------
change_sopts(Opts, S) ->
    SockOpts = lists:filter(fun(X) -> X =/= undefined end, Opts),
    S#s{sock_opts = SockOpts}.

%% ----------------------------------------------------------------------------
%% @doc parse response from modbus TCP slave device.
%% @enddoc
%% ----------------------------------------------------------------------------
parser(Chunk, #s{recv_buff = Buffer} = S) ->
    parser_(<<Buffer/binary, Chunk/binary>>, {ok, [], S#s.state}, S).

parser_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, {ok, Command, SS}, S) ->
    case cmd(Command, S#s{state = SS, recv_buff = Tail}) of
        {stop, _Reason, S3} ->
            parser__(Id, Payload, S3);
        S3 ->
            parser__(Id, Payload, S3)
    end;

parser_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, {stop, Reason, Command, SS}, S) ->
    {stop, _, S3} = cmd(Command, S#s{recv_buff = Tail, stage = {stop, Reason}, state = SS}),
    parser__(Id, Payload, S3);

parser_(<<_Id:16, 0:16, MsgLen:16, _Payload:MsgLen/binary, _Tail/binary>>, {'EXIT', Class, Reason, Strace}, _S) ->
    erlang:raise(Class, Reason, Strace);

parser_(<<_Id:16, _Other:16, _MsgLen:16, _/binary>>, _Res, S) ->
    {noreply, S#s{recv_buff = <<>>}};

parser_(Buffer, Res, S) ->
    resp_it(Res, S#s{recv_buff = Buffer}).

parser__(Id, <<DevNum:8, ?FUN_CODE_READ_HREGS:8, Len:8, BinData:Len/binary>>, S) ->
    LData = bin_to_list16(BinData, []),
    Msg = #read_register{type = holding, transaction_id = Id, device_number = DevNum, registers_value = LData},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_READ_IREGS:8, Len:8, BinData:Len/binary>>, S) ->
    LData = bin_to_list16(BinData, []),
    Msg = #read_register{type = input, transaction_id = Id, device_number = DevNum, registers_value = LData},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_READ_COILS:8, Len:8, BinData:Len/binary>>, S) ->
    Msg = #read_status{type = coil, transaction_id = Id, device_number = DevNum, registers_value = <<BinData:Len/binary>>},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_READ_INPUTS:8, Len:8, BinData:Len/binary>>, S) ->
    Msg = #read_status{type = input, transaction_id = Id, device_number = DevNum, registers_value = <<BinData:Len/binary>>},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>, S) ->
    Msg = #write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, _:16>>, S) ->
    Msg = #write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, Var:16>>, S) ->
    Value =
    case <<Var:16>> of
        <<0:16>> -> 0;
        <<16#FF00:16>> -> 1
    end,
    Msg = #write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16>>, S) ->
    Msg = #write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity},
    message(Msg, S);

parser__(Id, <<DevNum:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>>, S) ->
    Msg = #read_register{transaction_id = Id, type = input, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>>, S) ->
    Msg = #read_register{transaction_id = Id, type = holding, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_READ_COILS:8, Err_code:8>>, S) ->
    Msg = #read_status{transaction_id = Id, type = coil, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>>, S) ->
    Msg = #read_status{transaction_id = Id, type = input, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>>, S) ->
    Msg = #write_holding_register{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>>, S) ->
    Msg = #write_holding_registers{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>>, S) ->
    Msg = #write_coil_status{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    message(Msg, S);
parser__(Id, <<DevNum:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>>, S) ->
    Msg = #write_coils_status{transaction_id = Id, device_number = DevNum, error_code = Err_code},
    message(Msg, S);

parser__(_Id, <<_/binary>>, S) ->
    parser_(<<>>, {ok, [], S#s.state}, S).

%% ----------------------------------------------------------------------------
%% @doc message calllback invokes when master received response from slave.
%% @enddoc
%% ----------------------------------------------------------------------------
message(RegFun, S) ->
    Mod = S#s.mod,
    Res =
    try
        Mod:message(RegFun, S#s.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> erlang:raise(C, R, Stacktrace)
    end,
    parser_(S#s.recv_buff, Res, S).

%% ----------------------------------------------------------------------------
%% @doc transform binary(unit equal 16) to list of values.
%% @enddoc
%% ----------------------------------------------------------------------------
bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);
bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

%% ----------------------------------------------------------------------------
%% @doc transform list of values to binary(unit equal 16).
%% @enddoc
%% ----------------------------------------------------------------------------
list_to_bin16([], Acc) ->
    Acc;
list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).