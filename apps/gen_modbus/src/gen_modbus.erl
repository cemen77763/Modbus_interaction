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
    stream = {waiting, <<>>},
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

check_id(Data, <<Id:16, Other/binary>>) ->
    check_protocol(<<Other/binary, Data/binary>>, <<Id:16>>);
check_id(<<Id:16, Other/binary>>, Acc) ->
    case Other of
        <<>> -> {transaction, <<Acc/binary, Id:16>>};
        _ -> check_protocol(Other, <<Acc/binary, Id:16>>)
    end;
check_id(Data, Acc) ->
    {waiting, <<Acc/binary, Data/binary>>}.

check_protocol(Data, <<Id:16, 0:16, Other/binary>>) ->
    check_msglen(<<Other/binary, Data/binary>>, <<Id:16, 0:16>>);
check_protocol(<<0:16, Other/binary>>, Acc) ->
    case Other of
        <<>> -> {protocol, <<Acc/binary, 0:16>>};
        _ -> check_msglen(Other, <<Acc/binary, 0:16>>)
    end;
check_protocol(Data, Acc) ->
    {transaction, <<Acc/binary, Data/binary>>}.

check_msglen(Data, <<Id:16, 0:16, MsgLen:16, Other/binary>>) ->
    check_dev(<<Other/binary, Data/binary>>, <<Id:16, 0:16, MsgLen:16>>);
check_msglen(<<MsgLen:16, Other/binary>>, Acc) ->
    case Other of
        <<>> -> {msglen, <<Acc/binary, MsgLen:16>>};
        _ -> check_dev(Other, <<Acc/binary, MsgLen:16>>)
    end;
check_msglen(Data, Acc) ->
    {protocol, <<Acc/binary, Data/binary>>}.

check_dev(Data, <<Id:16, 0:16, MsgLen:16, Dev_num:8, Other/binary>>) ->
    check_dev(<<Other/binary, Data/binary>>, <<Id:16, 0:16, MsgLen:16, Dev_num:8>>);
check_dev(<<Dev_num:8, Other/binary>>, Acc) ->
    case Other of
        <<>> -> {dev_num, <<Acc/binary, Dev_num:8>>};
        _ -> check_funcode(Other, <<Acc/binary, Dev_num:8>>)
    end;
check_dev(Data, Acc) ->
    {msglen, <<Acc/binary, Data/binary>>}.

check_funcode(Data, <<Id:16, 0:16, MsgLen:16, Dev_num:8, Fun_code:8, Other/binary>>) ->
    check_action(Fun_code, <<Other/binary, Data/binary>>, <<Id:16, 0:16, MsgLen:16, Dev_num:8, Fun_code:8>>);
check_funcode(<<Fun_code:8, Other/binary>>, Acc) ->
    case Other of
        <<>> -> {Fun_code, <<Acc/binary, Fun_code:8>>};
        _ -> check_action(Fun_code, Other, <<Acc/binary, Fun_code:8>>)
    end;
check_funcode(Data, Acc) ->
    {dev_num, <<Acc/binary, Data/binary>>}.


check_action(?FUN_CODE_WRITE_HREG, <<_:16, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Len = (MsgLen - 4) * 8,
    case Other of
        <<>> ->
            {?FUN_CODE_WRITE_HREG, <<Acc/binary, Data/binary>>};
        <<_:Len>> ->
            {write_hreg, <<Acc/binary, Data/binary>>};
        <<_:Len, _/binary>> ->
            {write_hreg, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_WRITE_HREG, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_WRITE_HREG, Data, Acc) ->
    {?FUN_CODE_WRITE_HREG, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_WRITE_HREGS, <<_:16, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Len = (MsgLen - 4) * 8,
    case Other of
        <<_:Len>> ->
            {write_hregs, <<Acc/binary, Data/binary>>};
        <<_:Len, _/binary>> ->
            {write_hregs, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_WRITE_HREGS, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_WRITE_HREGS, Data, Acc) ->
    {?FUN_CODE_WRITE_HREGS, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_WRITE_COIL, <<_:16, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Len = (MsgLen - 4) * 8,
    case Other of
        <<_:Len>> ->
            {write_coil, <<Acc/binary, Data/binary>>};
        <<_:Len, _/binary>> ->
            {write_coil, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_WRITE_COIL, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_WRITE_COIL, Data, Acc) ->
    {?FUN_CODE_WRITE_COIL, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_WRITE_COILS, <<_:16, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Len = (MsgLen - 4) * 8,
    case Other of
        <<_:Len>> ->
            {write_coils, <<Acc/binary, Data/binary>>};
        <<_:Len, _/binary>> ->
            {write_coils, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_WRITE_COILS, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_WRITE_COILS, Data, Acc) ->
    {?FUN_CODE_WRITE_COILS, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_READ_IREGS, <<Bquantity:8, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Bquantity = MsgLen - 3,
    Len = Bquantity * 8,
    case Other of
        <<_:Len>> ->
            {read_iregs, <<Acc/binary, Data/binary>>};
        <<_:Len, _/binary>> ->
            {read_iregs, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_READ_IREGS, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_READ_IREGS, Data, Acc) ->
    {?FUN_CODE_READ_IREGS, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_READ_HREGS, <<Bquantity:8, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Bquantity = MsgLen - 3,
    Len = Bquantity * 8,
    case Other of
        <<>> ->
            {?FUN_CODE_READ_HREGS, <<Acc/binary, Data/binary>>};
        <<_:Len>> ->
            {read_hregs, <<Acc/binary, Data/binary>>};
        <<_:Len, _/binary>> ->
            {read_hregs, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_READ_HREGS, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_READ_HREGS, Data, Acc) ->
    {?FUN_CODE_READ_HREGS, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_READ_INPUTS, <<Len:8, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Len = MsgLen - 3,
    Dlen = Len * 8,
    case Other of
        <<_:Dlen>> ->
            {read_inputs, <<Acc/binary, Data/binary>>};
        <<_:Dlen, _/binary>> ->
            {read_inputs, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_READ_INPUTS, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_READ_INPUTS, Data, Acc) ->
    {?FUN_CODE_READ_INPUTS, <<Acc/binary, Data/binary>>};

check_action(?FUN_CODE_READ_COILS, <<Len:8, Other/binary>> = Data, <<_:32, MsgLen:16, _/binary>> = Acc) ->
    Len = MsgLen - 3,
    Dlen = Len * 8,
    case Other of
        <<_:Dlen>> ->
            {read_coils, <<Acc/binary, Data/binary>>};
        <<_:Dlen, _/binary>> ->
            {read_coils, <<Acc/binary, Data/binary>>};
        <<_/binary>> ->
            {?FUN_CODE_READ_COILS, <<Acc/binary, Data/binary>>}
    end;
check_action(?FUN_CODE_READ_COILS, Data, Acc) ->
    {?FUN_CODE_READ_COILS, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_READ_IREGS, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_read_iregs, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_READ_IREGS, Data, Acc) ->
    {?ERR_CODE_READ_IREGS, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_READ_HREGS, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_read_hregs, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_READ_HREGS, Data, Acc) ->
    {?ERR_CODE_READ_HREGS, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_READ_INPUTS, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_read_inputs, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_READ_INPUTS, Data, Acc) ->
    {?ERR_CODE_READ_INPUTS, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_READ_COILS, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_read_coils, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_READ_COILS, Data, Acc) ->
    {?ERR_CODE_READ_COILS, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_WRITE_HREG, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_write_hreg, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_WRITE_HREG, Data, Acc) ->
    {?ERR_CODE_WRITE_HREG, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_WRITE_HREGS, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_write_hregs, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_WRITE_HREGS, Data, Acc) ->
    {?ERR_CODE_WRITE_HREGS, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_WRITE_COIL, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_write_coil, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_WRITE_COIL, Data, Acc) ->
    {?ERR_CODE_WRITE_COIL, <<Acc/binary, Data/binary>>};

check_action(?ERR_CODE_WRITE_COILS, <<_ErrCode:8, _/binary>> = Data, Acc) ->
    {err_write_coils, <<Acc/binary, Data/binary>>};
check_action(?ERR_CODE_WRITE_COILS, Data, Acc) ->
    {?ERR_CODE_WRITE_COILS, <<Acc/binary, Data/binary>>}.

check_stream(Data, #state{stream = {waiting, Other}}) ->
    check_id(<<Other/binary, Data/binary>>, <<>>);
check_stream(Data, #state{stream = {transaction, Other}}) ->
    check_id(Data, Other);
check_stream(Data, #state{stream = {protocol, Other}}) ->
    check_protocol(Data, Other);
check_stream(Data, #state{stream = {msglen, Other}}) ->
    check_msglen(Data, Other);
check_stream(Data, #state{stream = {dev_num, Other}}) ->
    check_dev(Data, Other);
check_stream(Data, #state{stream = {fun_code, _Fun_codes, Other}}) ->
    check_funcode(Data, Other).

action({waiting, ResData}, S) ->
    {noreply, S#state{stream = {waiting, ResData}}};
action({transaction, ResData}, S) ->
    {noreply, S#state{stream = {transaction, ResData}}};
action({protocol, ResData}, S) ->
    {noreply, S#state{stream = {protocol, ResData}}};
action({msglen, Resdata}, S) ->
    {noreply, S#state{stream = {msglen, Resdata}}};
action({dev_num, Resdata}, S) ->
    {noreply, S#state{stream = {dev_num, Resdata}}};
action({?FUN_CODE_READ_COILS, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_READ_COILS, Resdata}}};
action({?FUN_CODE_READ_HREGS, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_READ_HREGS, Resdata}}};
action({?FUN_CODE_READ_INPUTS, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_READ_INPUTS, Resdata}}};
action({?FUN_CODE_READ_IREGS, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_READ_IREGS, Resdata}}};
action({?FUN_CODE_WRITE_COIL, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_WRITE_COIL, Resdata}}};
action({?FUN_CODE_WRITE_COILS, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_WRITE_COILS, Resdata}}};
action({?FUN_CODE_WRITE_HREG, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_WRITE_HREG, Resdata}}};
action({?FUN_CODE_WRITE_HREGS, Resdata}, S) ->
    {noreply, S#state{stream = {fun_code, ?FUN_CODE_WRITE_HREGS, Resdata}}};

action({read_iregs, <<TransId:16, 0:16, MsgLen:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, _/binary>> = ResData}, S) ->
    Len = (MsgLen - 3) * 8,
    <<_:72, BinData:Len, Something/binary>> = ResData,
    Mod = S#state.mod,
    LData = bin_to_list16(<<BinData:Len>>, []),
    Res =
    try
        Mod:message(#read_register{type = input, transaction_id = TransId, device_number = Dev_num, registers_value = LData}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({read_hregs, <<TransId:16, 0:16, MsgLen:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, _/binary>> = ResData}, S) ->
    Len = (MsgLen - 3) * 8,
    <<_:72, BinData:Len, Something/binary>> = ResData,
    Mod = S#state.mod,
    LData = bin_to_list16(<<BinData:Len>>, []),
    Res =
    try
        Mod:message(#read_register{type = holding, transaction_id = TransId, device_number = Dev_num, registers_value = LData}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({read_inputs, <<TransId:16, 0:16, MsgLen:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, _/binary>> = ResData}, S) ->
    Len = (MsgLen - 3) * 8,
    <<_:72, Bdata:Len, Something/binary>> = ResData,
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_status{type = input, transaction_id = TransId, device_number = Dev_num, registers_value = <<Bdata:Len>>}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({read_coils, <<TransId:16, 0:16, MsgLen:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, _/binary>> = ResData}, S) ->
    Len = (MsgLen - 3) * 8,
    <<_:72, Bdata:Len, Something/binary>> = ResData,
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_status{type = coil, transaction_id = TransId, device_number = Dev_num, registers_value = <<Bdata:Len>>}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({write_hreg, <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_register{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, register_value = Value}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({write_hregs, <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, _Reg_quantity:16, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_registers{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({write_coil, <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var:16, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Value =
    case <<Var:16>> of
        <<0:16>> -> 0;
        <<16#FF:8, 0:8>> -> 1
    end,
    Res =
    try
        Mod:message(#write_coil_status{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, register_value = Value}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({write_coils, <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COILS:8, Reg_num:16, Quantity:16, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coils_status{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, quantity = Quantity}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_read_hregs, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_HREGS:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_register{transaction_id = TransId, type = holding, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_read_iregs, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_IREGS:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_register{transaction_id = TransId, type = input, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_read_inputs, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_INPUTS:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_status{transaction_id = TransId, type = input, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_read_coils, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_READ_COILS:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#read_status{transaction_id = TransId, type = coil, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_write_hreg, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREG:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_register{transaction_id = TransId, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_write_hregs, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_HREGS:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_holding_registers{transaction_id = TransId, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_write_coil, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COIL:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coil_status{transaction_id = TransId, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}});

action({err_write_coils, <<TransId:16, 0:16, 3:16, Dev_num:8, ?ERR_CODE_WRITE_COILS:8, Err_code:8, Something/binary>>}, S) ->
    Mod = S#state.mod,
    Res =
    try
        Mod:message(#write_coils_status{transaction_id = TransId, device_number = Dev_num, error_code = Err_code}, S#state.state)
    catch
        throw:R -> {ok, R};
        C:R:Stacktrace -> {'EXIT', C, R, Stacktrace}
    end,
    msg_resp(Res, S#state{stream = {waiting, Something}}).

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
    msg_resp(Res, S#state{stream = {waiting, <<>>}});

handle_info({tcp, _Socket, Data}, S) ->
    action(check_stream(Data, S), S);

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
cmd([#connect{ip_addr = Ip_addr, port = Port} | T], #state{sock_info = #sock_info{socket = undefined}, stage = stop} = S) ->
    cmd_stop_connect(T, S, {Ip_addr, Port});
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
    cmd_disconnect(S2#state.mod, Reason, T, S2#state{stream = {waiting, <<>>}});
cmd([#disconnect{} | T], #state{sock_info = #sock_info{socket = undefined}, stage = stop} = S) ->
    cmd(T, S);
cmd([#disconnect{reason = Reason} | T], #state{stage = stop} = S) ->
    Socket = S#state.sock_info#sock_info.socket,
    gen_tcp:close(Socket),
    S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
    cmd_stop_disconnect(S2#state.mod, Reason, T, S2#state{stream = {waiting, <<>>}});
cmd([#disconnect{} | T], #state{stage = _} = S) ->
    cmd(T, S);

cmd([#read_register{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_register{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#read_register{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_stop_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#read_register{transaction_id = TransId, type = holding, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_hregs(T, {TransId, Dev_num, Reg_num, Quantity}, S);
cmd([#read_register{transaction_id = TransId, type = holding, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_hregs(T, {TransId, Dev_num, Reg_num, Quantity}, S);

cmd([#read_register{transaction_id = TransId, type = input, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_iregs(T, {TransId, Dev_num, Reg_num, Quantity}, S);
cmd([#read_register{transaction_id = TransId, type = input, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_iregs(T, {TransId, Dev_num, Reg_num, Quantity}, S);

cmd([#read_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#read_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#read_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_stop_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#read_status{transaction_id = TransId, type = coil, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_coils(T, {TransId, Dev_num, Reg_num, Quantity}, S);
cmd([#read_status{transaction_id = TransId, type = coil, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_coils(T, {TransId, Dev_num, Reg_num, Quantity}, S);

cmd([#read_status{transaction_id = TransId, type = input, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = stop} = S) ->
    read_inputs(T, {TransId, Dev_num, Reg_num, Quantity}, S);
cmd([#read_status{transaction_id = TransId, type = input, device_number = Dev_num, register_number = Reg_num, quantity = Quantity} | T], #state{stage = connect} = S) ->
    read_inputs(T, {TransId, Dev_num, Reg_num, Quantity}, S);

cmd([#write_holding_register{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_holding_register{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_holding_register{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_stop_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_holding_register{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = stop} = S) ->
    write_hreg(T, {TransId, Dev_num, Reg_num, Value}, S);
cmd([#write_holding_register{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = connect} = S) ->
    write_hreg(T, {TransId, Dev_num, Reg_num, Value}, S);

cmd([#write_holding_registers{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_holding_registers{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_holding_registers{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_stop_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_holding_registers{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, registers_value = Values} | T], #state{stage = stop} = S) ->
    write_hregs(T, {TransId, Dev_num, Reg_num, Values}, S);
cmd([#write_holding_registers{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_hregs(T, {TransId, Dev_num, Reg_num, Values}, S);

cmd([#write_coil_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_coil_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_coil_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_stop_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_coil_status{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = stop} = S) ->
    write_creg(T, {TransId, Dev_num, Reg_num, Value}, S);
cmd([#write_coil_status{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, register_value = Value} | T], #state{stage = connect} = S) ->
    write_creg(T, {TransId, Dev_num, Reg_num, Value}, S);

cmd([#write_coils_status{} | T], #state{stage = init} = S) ->
    cmd(T, S);
cmd([#write_coils_status{} | T], #state{stage = disconnect} = S) ->
    cmd_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_coils_status{} | T], #state{stage = stop, sock_info = #sock_info{socket = undefined}} = S) ->
    cmd_stop_disconnect(S#state.mod, socket_closed, T, S#state{stream = {waiting, <<>>}});
cmd([#write_coils_status{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, quantity = Quantity, registers_value = Values} | T], #state{stage = stop} = S) ->
    write_cregs(T, {TransId, Dev_num, Reg_num, Quantity, Values}, S);
cmd([#write_coils_status{transaction_id = TransId, device_number = Dev_num, register_number = Reg_num, quantity = Quantity, registers_value = Values} | T], #state{stage = connect} = S) ->
    write_cregs(T, {TransId, Dev_num, Reg_num, Quantity, Values}, S);

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
        {stop, _Reason, Command, S2} ->
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
        {stop, _Reason, Command, S2} ->
            cmd(T ++ Command, S#state{state = S2, stage = stop});
        {'EXIT', Class, Reason2, Strace} ->
            erlang:raise(Class, Reason2, Strace)
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

read_hregs(T, {TransId, Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 03 (чтение Holding reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            cmd_disconnect(S#state.mod, Reason, T, S)
    end.

read_iregs(T, {TransId, Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_IREGS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 04 (чтение Input reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

read_coils(T, {TransId, Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_COILS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 01 (чтение Coils status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

read_inputs(T, {TransId, Dev_num, Reg_num, Quantity}, S) ->
    Packet = <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_READ_INPUTS:8, Reg_num:16, Quantity:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 02 (чтение Inputs status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_hreg(T, {TransId, Dev_num, Reg_num, Value}, S) ->
    Packet = <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Value:16>>,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 06 (запись Holding reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_hregs(T, {TransId, Dev_num, Reg_num, Values}, S) ->
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,
    Mbap_len = (7 + Len),
    Packet_without_values = <<TransId:16, 0:16, Mbap_len:16, Dev_num:8, ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    Packet = list_to_bin16(Values, Packet_without_values),
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 10 (запись Holding reg)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_creg(T, {TransId, Dev_num, Reg_num, Value}, S) ->
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
            <<TransId:16, 0:16, 6:16, Dev_num:8, ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var/binary>>
    end,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 05 (запись Coil status)
    case gen_tcp:send(Socket, Packet) of
        ok ->
            cmd(T, S);
        {error, Reason} ->
            gen_tcp:close(Socket),
            S2 = S#state{sock_info = #sock_info{socket = undefined, connection = close}},
            cmd_disconnect(S2#state.mod, Reason, T, S2)
    end.

write_cregs(T, {TransId, Dev_num, Reg_num, Quantity, Values}, S) ->
    Packet = <<TransId:16, 0:16, 8:16, Dev_num:8, ?FUN_CODE_WRITE_COILS:8, Reg_num:16, Quantity:16, 1:8, Values:8>>,
    Socket = S#state.sock_info#sock_info.socket,
    % Modbus код функции 10 (запись Coils status)
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
    S#state{sock_opts = SocketOpts}.

bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);

bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).

list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).