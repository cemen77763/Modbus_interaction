%%% -----------------------------------------------------------------------------------------
%%% @doc behaviour to interact with modbus TCP devices
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

-include("gen_modbus.hrl").

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, false},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(state, {
    state = undefined,
    mod :: atom(),
    sock_info = #sock_info{},
    sock_opts = ?DEFAULT_SOCK_OPTS,
    stage = init
    }).

-type cmd() :: record:records().

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
            S2 = cmd(Command, #state{stage = init, mod = Mod, state = S}),
            case S2 of
                {stop, _S3} ->
                    {stop, shutdown};
                S2 ->
                    {ok, S2}
            end;
        {ok, Command, S, Timeout} ->
            S2 = cmd(Command, #state{stage = init, mod = Mod, state = S}),
            case S2 of
                {stop, _S3} ->
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
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
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
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {reply, Reply, S3}
            end;
        {reply, Reply, Command, S2, Timeout} ->
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {reply, Reply, S3, Timeout}
            end;
        {noreply, Command, S2} ->
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
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
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
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
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {noreply, S3}
            end;
        {stop, Reason, Command, S2} ->
            {stop, S3} = cmd(Command, S#state{stage = stop, state = S2}),
            {stop, Reason, S3};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
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
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, _:8, BinData/binary>>}, S) ->
    Mod = S#state.mod,
    LData = bin_to_list16(BinData, []),
    Res =
    try
        Mod:message(#read_holding_registers{device_number = Dev_num, registers_value = LData}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 5:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, _:8, BinData/binary>>}, S) ->
    Mod = S#state.mod,
    LData = bin_to_list16(BinData, []),
    Res =
    try
        Mod:message(#read_input_registers{device_number = Dev_num, registers_value = LData}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Bdata/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_coils_status{device_number = Dev_num, registers_value = Bdata}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Bdata/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_inputs_status{device_number = Dev_num, registers_value = Bdata}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Value}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, _Reg_quantity:16>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_registers{device_number = Dev_num, register_number = Reg_num}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COILS:8, Reg_num:16, Quantity:16>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var:16>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Var}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_holding_registers{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_input_registers{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_coils_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_inputs_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_register{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_registers{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coil_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

handle_info({tcp, _Socket, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coils_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S);

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
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
                S3 ->
                    {noreply, S3}
            end;
        {noreply, Command, S2, Timeout} ->
            S3 = cmd(Command, S#state{state = S2}),
            case S3 of
                {stop, S4} ->
                    {stop, shutdown, S4};
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
cmd([#connect{} | T], #state{stage = stop, sock_info = #sock_info{socket = _Socket}} = S) ->
    cmd(T, S);
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{stage = stop} = S) ->
    cmd_stop_connect(T, S, {Ip_addr, Port});
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{stage = _} = S) ->
    cmd_connect(T, S, {Ip_addr, Port});

cmd([#change_sock_opts{active = Active, reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = connect} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {active, Active}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    inet:setopts(S2#state.sock_info#sock_info.socket, S2#state.sock_opts),
    cmd(T, S2);
cmd([#change_sock_opts{active = Active, reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = stop} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {active, Active}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);
cmd([#change_sock_opts{active = Active, reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], #state{stage = _} = S) ->
    S2 = change_sopts([Ifaddr, binary, {packet, raw}, {active, Active}, {reuseaddr, Reuseaddr}, {nodelay, Nodelay}], S),
    cmd(T, S2);

cmd([#disconnect{reason = Reason} | T], #state{stage = connect} = S) ->
    Socket = S#state.sock_info#sock_info.socket,
    gen_tcp:close(Socket),
    S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
    cmd_disconnect(S2#state.mod, Reason, T, S2);
cmd([#disconnect{} | T], #state{sock_info = #sock_info{socket = undefined}, stage = stop} = S) ->
    cmd(T, S);
cmd([#disconnect{reason = Reason} | T], #state{stage = stop} = S) ->
    Socket = S#state.sock_info#sock_info.socket,
    gen_tcp:close(Socket),
    S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
    cmd_stop_disconnect(S2#state.mod, Reason, T, S2);
cmd([#disconnect{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#read_holding_registers{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_holding_registers{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_holding_registers{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_holding_registers{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_hregs(T, {Dev_num, Reg_num, Quantity}, S);
cmd([#read_holding_registers{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_hregs(T, {Dev_num, Reg_num, Quantity}, S);

cmd([#read_input_registers{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_input_registers{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_input_registers{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_input_registers{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_iregs(T, {Dev_num, Reg_num, Quantity}, S);
cmd([#read_input_registers{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_iregs(T, {Dev_num, Reg_num, Quantity}, S);

cmd([#read_coils_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_coils_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_coils_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_coils_status{} | T], #state{sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_coils(T, {Dev_num, Reg_num, Quantity}, S);
cmd([#read_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_coils(T, {Dev_num, Reg_num, Quantity}, S);

cmd([#read_inputs_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_inputs_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_inputs_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_inputs_status{} | T], #state{sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#read_inputs_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_inputs(T, {Dev_num, Reg_num, Quantity}, S);
cmd([#read_inputs_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_inputs(T, {Dev_num, Reg_num, Quantity}, S);

cmd([#write_holding_register{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_holding_register{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_holding_register{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_holding_register{} | T], #state{sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = stop} = S) ->
    write_hreg(T, {Dev_num, Reg_num, Value}, S);
cmd([#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = connect} = S) ->
    write_hreg(T, {Dev_num, Reg_num, Value}, S);

cmd([#write_holding_registers{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_holding_registers{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_holding_registers{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_holding_registers{} | T], #state{sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_holding_registers{device_number = Dev_num, register_number = Reg_num, registers_value = Values} | T], #state{stage = stop} = S) ->
    write_hregs(T, {Dev_num, Reg_num, Values}, S);
cmd([#write_holding_registers{device_number = Dev_num, register_number = Reg_num, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_hregs(T, {Dev_num, Reg_num, Values}, S);

cmd([#write_coil_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_coil_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_coil_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_coil_status{} | T], #state{sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = stop} = S) ->
    write_creg(T, {Dev_num, Reg_num, Value}, S);
cmd([#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = connect} = S) ->
    write_creg(T, {Dev_num, Reg_num, Value}, S);

cmd([#write_coils_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_coils_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_coils_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_coils_status{} | T], #state{sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S);
cmd([#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity, registers_value = Values} | T], #state{stage = stop} = S) ->
    write_cregs(T, {Dev_num, Reg_num, Quantity, Values}, S);
cmd([#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_cregs(T, {Dev_num, Reg_num, Quantity, Values}, S);

cmd([], #state{stage = stop} = S) ->
    {stop, S};
cmd([], S) ->
    S.

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
            cmd(T ++ Command, S#state{state = S2, stage = disconnect});
        {stop, Reason, Command, S2} ->
            cmd(T ++ Command, S#state{state = S2, stage = stop});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

cmd_stop_disconnect(Mod, Reason, T, S) ->
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
            cmd(T ++ Command, S#state{state = S2, stage = stop});
        {stop, Reason, Command, S2} ->
            cmd(T ++ Command, S#state{state = S2, stage = stop});
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

cmd_connect(T, S, {Ip_addr, Port}) ->
    Mod = S#state.mod,
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.sock_opts) of
        {ok, _} ->
            S2 = S#state{sock_info = #sock_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port,
                connection = connect},
                stage = connect},
            Res =
            try
                Mod:connect(S2#state.sock_info, S2#state.state)
            catch
                throw:R -> {ok, R};
                C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
            end,
            case Res of
                {ok, Command, S3} ->
                    cmd(T ++ Command, S2#state{state = S3, stage = connect});
                {stop, _Reason, Command, S3} ->
                    cmd(T ++ Command, S2#state{state = S3, stage = stop});
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

cmd_stop_connect(T, S, {Ip_addr, Port}) ->
    Mod = S#state.mod,
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.sock_opts) of
        {ok, _} ->
            S2 = S#state{sock_info = #sock_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port,
                connection = connect},
                stage = stop},
            Res =
            try
                Mod:connect(S2#state.sock_info, S2#state.state)
            catch
                throw:R -> {ok, R};
                C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
            end,
            case Res of
                {ok, Command, S3} ->
                    cmd(T ++ Command, S2#state{state = S3, stage = stop});
                {stop, _Reason, Command, S3} ->
                    cmd(T ++ Command, S2#state{state = S3, stage = stop});
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            S2 = S#state{stage = stop, sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

read_hregs(T, {Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 03 (чтение Holding reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
        case gen_tcp:recv(Socket, 0, 1000) of
            {ok, <<1:16, 0:16, _:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, _:8, BinData/binary>>} ->
                LData = bin_to_list16(BinData, []),
                Res =
                try
                    Mod:message(#read_holding_registers{device_number = Dev_num,
                    register_number = Reg_num,
                    quantity = Quantity,
                    registers_value = LData
                    }, S#state.state)
                catch
                    throw:R -> {ok, R};
                    C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                end,
                case Res of
                    {ok, Command, S2} ->
                        cmd(T ++ Command, S#state{state = S2});
                    {stop, _Reason, Command, S2} ->
                        cmd(T ++ Command, S#state{stage = stop, state = S2});
                    {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                end;
            {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>>} ->
                Res =
                    try
                        Mod:message(#read_holding_registers{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
            {ok, _Else} ->
                cmd(T, S);
            {error, Reason} ->
                Res =
                try
                    Mod:message({error, Reason}, S#state.state)
                catch
                    throw:R -> {ok, R};
                    C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                end,
                case Res of
                    {ok, Command, S2} ->
                        cmd(T ++ Command, S#state{state = S2});
                    {stop, _Reason, Command, S2} ->
                        cmd(T ++ Command, S#state{stage = stop, state = S2});
                    {'EXIT', Class, Reason, Strace} ->
                        erlang:raise(Class, Reason, Strace)
                end
        end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            cmd_disconnect(S#state.mod, Reason, T, S)
    end.

read_iregs(T, {Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, 1:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 04 (чтение Input reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 5:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, _:8, BinData/binary>>} ->
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
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#read_input_registers{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

read_coils(T, {Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 01 (чтение Coils status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Bdata/binary>>} ->
                    Res =
                    try
                        Mod:message(#read_coils_status{
                            device_number = Dev_num,
                            register_number = Reg_num,
                            quantity = Quantity,
                            registers_value = Bdata
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#read_coils_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

read_inputs(T, {Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 02 (чтение Inputs status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 4:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Bdata/binary>>} ->
                    Res =
                    try
                        Mod:message(#read_inputs_status{
                            device_number = Dev_num,
                            register_number = Reg_num,
                            quantity = Quantity,
                            registers_value = Bdata
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#read_inputs_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_hreg(T, {Dev_num, Reg_num, Value}, S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 06 (запись Holding reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>} ->
                    Res =
                    try
                        Mod:message(#write_holding_register{
                            device_number = Dev_num,
                            register_number = Reg_num,
                            register_value = Value
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#write_holding_register{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_hregs(T, {Dev_num, Reg_num, Values}, S) ->
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,
    Mbap_len = (7 + Len),
    Packet_without_values = <<1:16, 0:16, Mbap_len:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    Packet = list_to_bin16(Values, Packet_without_values),
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 10 (запись Holding reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16>>} ->
                    Res =
                    try
                        Mod:message(#write_holding_registers{
                            device_number = Dev_num,
                            register_number = Reg_num,
                            registers_value = Values
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#write_holding_registers{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_creg(T, {Dev_num, Reg_num, Value}, S) ->
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
            <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var/binary>>
    end,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 05 (запись Coil status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var2:16>>} ->
                    Res =
                    try
                        Mod:message(#write_coil_status{
                            device_number = Dev_num,
                            register_number = Reg_num,
                            register_value = Var2
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#write_coil_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_cregs(T, {Dev_num, Reg_num, Quantity, Values}, S) ->
    Packet = <<1:16, 0:16, 8:16, Dev_num:8, ?FUN_CODE_WRITE_COILS:8, Reg_num:16, Quantity:16, 1:8, Values:8>>,
    Socket = S#state.sock_info#sock_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 05 (запись Coil status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COILS:8, Reg_num:16, Quantity:16>>} ->
                    Res =
                    try
                        Mod:message(#write_coils_status{
                            device_number = Dev_num,
                            register_number = Reg_num,
                            registers_value = Values,
                            quantity = Quantity
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>>} ->
                    Res =
                    try
                        Mod:message(#write_coils_status{device_number = Dev_num, error_code = Err_code}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, _Else} ->
                    cmd(T, S);
                {error, Reason} ->
                    Res =
                    try
                        Mod:message({error, Reason}, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, _Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{stage = stop, state = S2});
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

change_sopts(Opts, S) when is_list(Opts) ->
    SocketOpts = lists:filter(fun(X) -> X =/= undefined end, Opts),
    S#state{sock_opts = SocketOpts}.

bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);

bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).