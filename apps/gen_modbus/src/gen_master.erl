%%% -----------------------------------------------------------------------------------------
%%% @doc Behaviour to interact with modbus TCP devices
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(gen_master).

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
    state :: term(),
    mod :: atom(),
    sock_info = #sock_info{},
    sock_opts = ?DEFAULT_SOCK_OPTS,
    recv_buff = <<>>,
    send_buff = <<>>,
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
                {stop, Reason, _S2} ->
                    {stop, Reason};
                S2 ->
                    {ok, S2}
            end;
        {ok, Command, S, Timeout} ->
            case cmd(Command, #state{stage = init, mod = Mod, state = S}) of
                {stop, Reason, _S2} ->
                    {stop, Reason};
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
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Command, S2} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = S2});
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
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {reply, Reply, S3}
            end;
        {reply, Reply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {reply, Reply, S3, Timeout}
            end;
        {noreply, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Reply, Command, S2} ->
            {stop, Reason, S3} = cmd(Command, S#state{stage = {stop, Reason}, state = S2}),
            {stop, Reason, Reply, S3};
        {stop, Reason, Command, S2} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = S2});
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
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Command, S2} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = S2});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

msg_resp(Res, S) ->
    case Res of
        {ok, Command, S2} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3}
            end;
        {stop, Reason, Command, S2} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = S2});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

handle_info({tcp_closed, Socket}, S) when Socket =:= S#state.sock_info#sock_info.socket ->
    gen_tcp:close(Socket),
    Res = disconnect_it(connection_closed, S),
    msg_resp(Res, S#state{stage = disconnect, send_buff = <<>>, recv_buff = <<>>, sock_info = #sock_info{socket = undefined}});

handle_info({tcp, Socket, Data}, S) when Socket =:= S#state.sock_info#sock_info.socket ->
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
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            case cmd(Command, S#state{state = S2}) of
                {stop, Reason, S3} ->
                    {stop, Reason, S3};
                S3 ->
                    {noreply, S3, Timeout}
            end;
        {stop, Reason, Command, S2} ->
            cmd(Command, S#state{stage = {stop, Reason}, state = S2});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.


terminate(Reason, S) ->
    Mod = S#state.mod,
    Socket = S#state.sock_info#sock_info.socket,
    Socket =/= undefined andalso
        gen_tcp:close(Socket),
    case disconnect_it(shutdown, S) of
        {ok, Command, S2} ->
            S3 = cmd(Command, S#state{sock_info = #sock_info{socket = undefined}, send_buff = <<>>, recv_buff = <<>>, stage = disconnect, state = S2}),
            terminate_it(Mod, Reason, S3);
        {stop, Reason2, Command, S2} ->
            {stop, Reason3, S3} = cmd(Command, S#state{send_buff = <<>>, recv_buff = <<>>, state = S2, stage = {stop, Reason2}, sock_info = #sock_info{socket = undefined}}),
            terminate_it(Mod, Reason3, S3)
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

code_change(_OldVsn, S, _Extra) ->
    {ok, S}.

cmd([#connect{} | T], #state{stage = connect} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});
cmd([#connect{} | T], #state{stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{stage = _} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});

cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = connect} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#state.sock_info#sock_info.socket, S2#state.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = {stop, _Reason}} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#state.sock_info#sock_info.socket, S2#state.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = _} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);

cmd([#disconnect{reason = Reason} | T], #state{stage = connect} = S) ->
    cmd_disconnect(T, Reason, S);
cmd([#disconnect{} | T], #state{sock_info = #sock_info{socket = undefined}, stage = {stop, _Reason}} = S) ->
    cmd(T, S);
cmd([#disconnect{reason = Reason} | T], #state{stage = {stop, Reason}} = S) ->
    cmd_disconnect(T, Reason, S);
cmd([#disconnect{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#read_register{transaction_id = Id, type = holding, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = {stop, _Reason}} = S) ->
    read_hregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{transaction_id = Id, type = holding, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_hregs(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_register{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = {stop, _Reason}} = S) ->
    read_iregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_iregs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_register{} | T], #state{stage = init} = S) ->
    cmd(T, S);

cmd([#read_status{transaction_id = Id, type = coil, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = {stop, _Reason}} = S) ->
    read_coils(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{transaction_id = Id, type = coil, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_coils(T, {Id, DevNum, RegNum, Quantity}, S);

cmd([#read_status{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = {stop, _Reason}} = S) ->
    read_inputs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{transaction_id = Id, type = input, device_number = DevNum, register_number = RegNum, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_inputs(T, {Id, DevNum, RegNum, Quantity}, S);
cmd([#read_status{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = {stop, _Reason}} = S) ->
    write_hreg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_holding_register{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = connect} = S) ->
    write_hreg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_holding_register{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum, registers_value = Values} | T], #state{stage = {stop, _Reason}} = S) ->
    write_hregs(T, {Id, DevNum, RegNum, Values}, S);
cmd([#write_holding_registers{transaction_id = Id, device_number = DevNum, register_number = RegNum, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_hregs(T, {Id, DevNum, RegNum, Values}, S);
cmd([#write_holding_registers{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = {stop, _Reason}} = S) ->
    write_creg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_coil_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, register_value = Value} | T], #state{stage = connect} = S) ->
    write_creg(T, {Id, DevNum, RegNum, Value}, S);
cmd([#write_coil_status{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity, registers_value = Values} | T], #state{stage = {stop, _Reason}} = S) ->
    write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S);
cmd([#write_coils_status{transaction_id = Id, device_number = DevNum, register_number = RegNum, quantity = Quantity, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, S);
cmd([#write_coils_status{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([], #state{stage = {stop, Reason}} = S) ->
    case S#state.send_buff of
        <<>> ->
            {stop, Reason, S};
        <<_Packet/binary>> ->
            send_message(S)
    end;
cmd([], S) ->
    case S#state.send_buff of
        <<>> ->
            S;
        <<_Packet/binary>> ->
            send_message(S)
    end.

disconnect_it(Reason, S) ->
    Mod = S#state.mod,
    try
        Mod:disconnect(Reason, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

cmd_disconnect(T, Reason, #state{stage = {stop, Reason}} = S) ->
    Socket = S#state.sock_info#sock_info.socket,
    Socket =/= undefined andalso
        gen_tcp:close(Socket),
    S2 = S#state{send_buff = <<>>, recv_buff = <<>>, sock_info = #sock_info{socket = undefined}},
    case disconnect_it(Reason, S2) of
        {ok, Command, S3} ->
            cmd(Command ++ T, S2#state{state = S3, stage = {stop, Reason}});
        {stop, _Reason, Command, S3} ->
            cmd(Command ++ T, S2#state{state = S3, stage = {stop, Reason}});
        {'EXIT', Class, Reason2, Strace} ->
            erlang:raise(Class, Reason2, Strace)
    end;
cmd_disconnect(T, Reason, S) ->
    Socket = S#state.sock_info#sock_info.socket,
    Socket =/= undefined andalso
        gen_tcp:close(Socket),
    S2 = S#state{send_buff = <<>>, recv_buff = <<>>, sock_info = #sock_info{socket = undefined}},
    case disconnect_it(Reason, S2) of
        {ok, Command, S3} ->
            cmd(Command ++ T, S2#state{state = S3, stage = disconnect});
        {stop, _Reason, Command, S3} ->
            cmd(Command ++ T, S2#state{state = S3, stage = {stop, Reason}});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

connect_it(S) ->
    Mod = S#state.mod,
    try
        Mod:connect(S#state.sock_info, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end.

cmd_connect(T, #state{stage = {stop, Reason}} = S, {Ip_addr, Port}) ->
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.sock_opts) of
        {ok, _} ->
            S2 = S#state{sock_info = #sock_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port}},
            case connect_it(S2) of
                {ok, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = {stop, Reason}});
                {stop, _Reason, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = {stop, Reason}});
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            cmd_disconnect(T, Reason, S#state{stage = {stop, Reason}})
    end;
cmd_connect(T, S, {IpAddr, Port}) ->
    case {_, Socket} = gen_tcp:connect(IpAddr, Port, S#state.sock_opts) of
        {ok, _} ->
            S2 = S#state{sock_info = #sock_info{
                socket = Socket,
                ip_addr = IpAddr,
                port = Port}},
            case connect_it(S2) of
                {ok, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = connect});
                {stop, Reason, Command, S3} ->
                    cmd(Command ++ T, S2#state{state = S3, stage = {stop, Reason}});
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            cmd_disconnect(T, Reason, S)
    end.

read_hregs(T, {Id, DevNum, RegNum, Quantity}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_HREGS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

read_iregs(T, {Id, DevNum, RegNum, Quantity}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_IREGS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

read_coils(T, {Id, DevNum, RegNum, Quantity}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_COILS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

read_inputs(T, {Id, DevNum, RegNum, Quantity}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_READ_INPUTS:8, RegNum:16, Quantity:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

write_hreg(T, {Id, DevNum, RegNum, Value}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

write_hregs(T, {Id, DevNum, RegNum, Values}, #state{send_buff = Buff} = S) ->
    RegQuantity = length(Values),
    Len = RegQuantity * 2,
    Mbap_len = (7 + Len),
    PacketWithoutValues = <<Id:16, 0:16, Mbap_len:16, DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, RegQuantity:16, Len:8>>,
    Packet = list_to_bin16(Values, PacketWithoutValues),
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

write_creg(T, {Id, DevNum, RegNum, 0}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>});
write_creg(T, {Id, DevNum, RegNum, 1}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>});
write_creg(T, {_, _, _, undefined}, S) ->
    cmd(T, S).

write_cregs(T, {Id, DevNum, RegNum, Quantity, Values}, #state{send_buff = Buff} = S) ->
    Packet = <<Id:16, 0:16, 8:16, DevNum:8, ?FUN_CODE_WRITE_COILS:8, RegNum:16, Quantity:16, 1:8, Values:8>>,
    cmd(T, S#state{send_buff = <<Buff/binary, Packet/binary>>}).

send_message(S) ->
    Socket = S#state.sock_info#sock_info.socket,
    Packet = S#state.send_buff,
    R = gen_tcp:send(Socket, Packet),
    send_message_(S#state{send_buff = <<>>}, R).
send_message_(#state{stage = {stop, Reason}} = S, ok) -> {stop, Reason, S};
send_message_(S, ok) -> S;
send_message_(S, {error, Reason}) -> cmd_disconnect([], Reason, S).

change_sopts(Opts, S) ->
    SockOpts = lists:filter(fun(X) -> X =/= undefined end, Opts),
    S#state{sock_opts = SockOpts}.

parser(Chunk, #state{recv_buff = Buffer} = S) ->
    parser_(<<Buffer/binary, Chunk/binary>>, {ok, [], S#state.state}, S).

parser_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, Res, S) ->
    case Res of
        {ok, Command, S2} ->
            case cmd(Command, S#state{state = S2, recv_buff = Tail}) of
                {stop, _Reason, S3} ->
                    parser__(Id, Payload, S3);
                S3 ->
                    parser__(Id, Payload, S3)
            end;
        {stop, Reason, Command, S2} ->
            {stop, _, S3} = cmd(Command, S#state{recv_buff = Tail, stage = {stop, Reason}, state = S2}),
            parser__(Id, Payload, S3);
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end;

parser_(Buffer, Res, S) ->
    msg_resp(Res, S#state{recv_buff = Buffer}).

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
    message(Msg, S).

message(RegFun, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(RegFun, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> erlang:raise(C, R, Stacktrace)
    end,
    parser_(S#state.recv_buff, Res, S).

bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);
bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

list_to_bin16([], Acc) ->
    Acc;
list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).