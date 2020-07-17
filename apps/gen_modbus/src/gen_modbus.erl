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

-include("../include/gen_modbus.hrl").

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, false},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(state, {
    state = 0,
    mod :: atom(),
    socket_info = #socket_info{},
    socket_opts = ?DEFAULT_SOCK_OPTS
    }).

-type cmd() :: record:records().

-type netinfo() :: [gen_tcp:connect_option()].

%%% -----------------------------------------------------------------------------------------
%%% API
%%% -----------------------------------------------------------------------------------------

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
            {ok, cmd(Command, #state{mod = Mod, state = S})};
        {ok, Command, S, Timeout} ->
            {ok, cmd(Command, #state{mod = Mod, state = S}), Timeout};
        {stop, Command, Reason} ->
            cmd(Command, #state{mod = Mod}),
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
            {noreply, cmd(Command, S#state{state = S2})};
        {noreply, Command, S2, Timeout} ->
            {noreply, cmd(Command, S#state{state = S2}), Timeout};
        {stop, Reason, Command, S2} ->
            {stop, Reason, cmd(Command, S#state{state = S2})};
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
            {reply, Reply, cmd(Command, S#state{state = S2})};
        {reply, Reply, Command, S2, Timeout} ->
            {reply, Reply, cmd(Command, S#state{state = S2}), Timeout};
        {noreply, Command, S2} ->
            {noreply, cmd(Command, S#state{state = S2})};
        {noreply, Command, S2, Timeout} ->
            {noreply, cmd(Command, S#state{state = S2}), Timeout};
        {stop, Reason, Reply, Command, S2} ->
            {stop, Reason, Reply, cmd(Command, S#state{state = S2})};
        {stop, Reason, Command, S2} ->
            {stop, Reason, cmd(Command, S#state{state = S2})};
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
            {noreply, cmd(Command, S#state{state = S2})};
        {noreply, Command, S2, Timeout} ->
            {noreply, cmd(Command, S#state{state = S2}), Timeout};
        {stop, Reason, Command, S2} ->
            {stop, Reason, cmd(Command, S#state{state = S2})};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

handle_info({tcp_closed, #state{socket_info = #socket_info{socket = Socket}} = S}, S) ->
    Mod = S#state.mod,
    Socket = S#state.socket_info#socket_info.socket,
    gen_tcp:close(Socket),
    Res =
    try
        Mod:disconnect(connection_closed, S#state.state)
    catch
            throw:R -> {ok, R};
            C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    case Res of
        {ok, Command, S2} ->
            {noreply, cmd(Command, S#state{state = S2})};
        {stop, Reason, Command, S2} ->
            {stop, Reason, cmd(Command, S#state{state = S2})};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end;

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
            {noreply, cmd(Command, S#state{state = S2})};
        {noreply, Command, S2, Timeout} ->
            {noreply, cmd(Command, S#state{state = S2}), Timeout};
        {stop, Reason, Command, S2} ->
            {stop, Reason, cmd(Command, S#state{state = S2})};
        {'EXIT', Class, Reason, Strace} ->
            erlang:raise(Class, Reason, Strace)
    end.

terminate(Reason, S) ->
    Mod = S#state.mod,
    Socket = S#state.socket_info#socket_info.socket,
    case Socket of
        0 -> ok;
        _ -> gen_tcp:close(S#state.socket_info#socket_info.socket)
    end,
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

cmd([#connect{ip_addr = Ip_addr, port = Port} | T], S) ->
    Mod = S#state.mod,
    case S#state.socket_info#socket_info.socket of
        0 -> ok;
        _ -> gen_tcp:close(S#state.socket_info#socket_info.socket)
    end,
    case {_, Socket} = gen_tcp:connect(Ip_addr, Port, S#state.socket_opts) of
        {ok, _} ->
            S2 = S#state{socket_info = #socket_info{
                socket = Socket,
                ip_addr = Ip_addr,
                port = Port,
                connection = connect}},
            Res =
            try
                Mod:connect(S2#state.socket_info, S2#state.state)
            catch
                throw:R -> {ok, R};
                C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
            end,
            case Res of
                {ok, Command, S3} ->
                    cmd(T ++ Command, S2#state{state = S3});
                {stop, Reason, Command, S3} ->
                    cmd(T ++ Command, S2#state{state = S3}),
                    gen_server:stop(self(), Reason, infinity);
                {'EXIT', Class, Reason, Strace} ->
                    erlang:raise(Class, Reason, Strace)
            end;
        {error, Reason} ->
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#change_sock_opts{active = Active, reuseaddr = Reuseaddr, nodelay = Nodelay, ifaddr = Ifaddr} | T], S) ->
    S2 = S#state{socket_opts = [
        Ifaddr,
        binary,
        {packet, raw},
        {active, Active},
        {reuseaddr, Reuseaddr},
        {nodelay, Nodelay}
        ]},
    Socket = S2#state.socket_info#socket_info.socket,
    case Socket of
        0 -> ok;
        _ -> inet:setopts(Socket, S2#state.socket_opts)
    end,
    cmd(T, S2);

cmd([#disconnect{reason = Reason} | T], S) ->
    Socket = S#state.socket_info#socket_info.socket,
    case Socket of
        0 -> ok;
        _ -> gen_tcp:close(Socket)
    end,
    S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
    disconnect_cmd(S2#state.mod, Reason, T, S2);

cmd([#read_holding_registers{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#read_holding_registers{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.socket_info#socket_info.socket,
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
                    {stop, Reason, Command, S2} ->
                        cmd(T ++ Command, S#state{state = S2}),
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                end;
            {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8>>} ->
                decryption_error_code:decrypt(Err_code),
                cmd(T, S);
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
                        cmd(T ++ Command, S#state{state = S2}),
                        gen_server:stop(self(), Reason, infinity);
                    {'EXIT', Class, Reason, Strace} ->
                        erlang:raise(Class, Reason, Strace)
                end
        end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#read_input_registers{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#read_input_registers{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, 1:16>>,
    Socket = S#state.socket_info#socket_info.socket,
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
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#read_coils_status{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#read_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.socket_info#socket_info.socket,
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
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#read_inputs_status{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#read_inputs_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.socket_info#socket_info.socket,
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
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#write_holding_register{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], S) ->
    Packet = <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>,
    Socket = S#state.socket_info#socket_info.socket,
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
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#write_holding_registers{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#write_holding_registers{device_number = Dev_num, register_number = Reg_num, registers_value = Values} | T], S) ->
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,
    Mbap_len = (7 + Len),
    Packet_without_values = <<1:16, 0:16, Mbap_len:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    Packet = list_to_bin16(Values, Packet_without_values),
    Socket = S#state.socket_info#socket_info.socket,
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
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#write_coils_status{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = Quantity, registers_value = Value} | T], S) ->
    Packet = <<1:16, 0:16, 8:16, Dev_num:8, ?FUN_CODE_WRITE_COILS:8, Reg_num:16, Quantity:16, 1:8, Value:8>>,
    Socket = S#state.socket_info#socket_info.socket,
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
                            registers_value = Value,
                            quantity = Quantity
                            }, S#state.state)
                    catch
                        throw:R -> {ok, R};
                        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
                    end,
                    case Res of
                        {ok, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2});
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([#write_coil_status{} | T], #state{socket_info = #socket_info{socket = 0}} = S) ->
    disconnect_cmd(S#state.mod, socket_closed, T, S);

cmd([#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], S) ->
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
    Socket = S#state.socket_info#socket_info.socket,
    Mod = S#state.mod,
    % Modbus код функции 05 (запись Coil status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            case gen_tcp:recv(Socket, 0, 1000) of
                {ok, <<1:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var:16>>} ->
                    Res =
                    try
                        Mod:message(#write_coil_status{
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
                        {stop, Reason, Command, S2} ->
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end;
                {ok, <<1:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8>>} ->
                    decryption_error_code:decrypt(Err_code),
                    cmd(T, S);
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
                            cmd(T ++ Command, S#state{state = S2}),
                            gen_server:stop(self(), Reason, infinity);
                        {'EXIT', Class, Reason, Strace} ->
                            erlang:raise(Class, Reason, Strace)
                    end
            end;
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{socket_info = #socket_info{socket = 0, connection = close}},
            disconnect_cmd(S2#state.mod, Reason, T, S2)
    end;

cmd([], S) ->
    S.

disconnect_cmd(Mod, Reason, T, S) ->
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
            cmd(T ++ Command, S#state{state = S2});
        {stop, Reason, Command, S2} ->
            cmd(T ++ Command, S#state{state = S2}),
            gen_server:stop(self(), Reason, infinity);
        {'EXIT', Class, Reason, Strace} ->
    erlang:raise(Class, Reason, Strace)
    end.


bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);

bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).