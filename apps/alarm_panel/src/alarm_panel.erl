%%% ---------------------------------------------------------------------------
%%% @doc modbus tcp panel have 5 alarm coils (coil registers 0...4)
%%% @end
%%% ---------------------------------------------------------------------------
-module(alarm_panel).

-behaviour(gen_slave).

-include_lib("gen_slave/include/gen_slave.hrl").

-define(DEVICE_NUM, 2).

-define(ALARM_NUM, 5).

-define(PORT, 5000).

-record(s, {
    coils = 0,
    allowed_connections = 5,
    active_socks = []
    }).

-export([
    start/0,
    stop/0,
    alarm/2,
    status/0
    ]).

-export([
    init/1,
    connect/2,
    handle_call/3,
    handle_continue/2,
    handle_info/2,
    handle_cast/2,
    disconnect/3,
    message/3,
    terminate/2
    ]).

%%% ---------------------------------------------------------------------------
%%% @doc start gen_slave.
%%% @end
%%% ---------------------------------------------------------------------------
start() ->
    gen_slave:start_link({local, ?MODULE}, ?MODULE, [?PORT, ?DEVICE_NUM], []).

%%% ---------------------------------------------------------------------------
%%% @doc stop gen slave.
%%% @end
%%% ---------------------------------------------------------------------------
stop() ->
    gen_slave:stop(?MODULE).

%%% ---------------------------------------------------------------------------
%%% @doc change indicator on the alarm panel (Status => off | on, Type => 1..5)
%%% .
%%% @end
%%% ---------------------------------------------------------------------------
alarm(Status, Type) when Type =< ?ALARM_NUM ->
    gen_slave:cast(?MODULE, {alarm, Status, Type}).

%%% ---------------------------------------------------------------------------
%%% @doc return state list of coil registers => [1, 2, 3, 4, 5].
%%% @end
%%% ---------------------------------------------------------------------------
status() ->
    gen_slave:call(?MODULE, get_status).

%%% ---------------------------------------------------------------------------
%%% @doc init gen_slave with default state.
%%% @end
%%% ---------------------------------------------------------------------------
init([]) ->
    {ok, [wait_connect], #s{}}.

%%% ---------------------------------------------------------------------------
%%% @doc when master device connect.
%%% @end
%%% ---------------------------------------------------------------------------
connect(Sock, #s{allowed_connections = Connections, active_socks = ASocks} = S) ->
    case Connections > 0 of
        true ->
            io:format("Alarm panel connected to ~w.~n", [Sock]),
            {ok, [wait_connect], S#s{active_socks = [Sock | ASocks], allowed_connections = Connections - 1}};
        _ ->
            io:format("Alarm panel connections limit reached.~n"),
            {ok, [], S}
    end.

%%% ---------------------------------------------------------------------------
%%% @doc when master device disconnect.
%%% @end
%%% ---------------------------------------------------------------------------
disconnect(Sock, Reason, #s{active_socks = ASocks, allowed_connections = Connections} = S) ->
    io:format("Alarm panel disconnected because ~w from ~w.~n", [Reason, Sock]),
    {ok, [wait_connect], S#s{active_socks = lists:delete(Sock, ASocks), allowed_connections = Connections + 1}}.

%%% ---------------------------------------------------------------------------
%%% @doc receive write and read coils message and send confirm message, on
%%% other messages send error.
%%% @end
%%% ---------------------------------------------------------------------------
message(#write_coil{reg_num = RegNum, val = 1, response = Resp}, Socket, #s{coils = C} = S) when RegNum < ?ALARM_NUM ->
    C2 = C bor (1 bsl RegNum),
    {ok, [#response{socket = Socket, response = Resp}], S#s{coils = C2}};

message(#write_coil{reg_num = RegNum, val = 0, response = Resp}, Socket, #s{coils = C} = S) when RegNum < ?ALARM_NUM ->
    C2 = C band (bnot (1 bsl RegNum)),
    {ok, [#response{socket = Socket, response = Resp}], S#s{coils = C2}};

message(#write_coils{reg_num = RegNum, quantity = Quantity, val = Val, response = Resp}, Socket, #s{coils = C} = S) when (Quantity + RegNum) =< ?ALARM_NUM ->
    Val2 = Val bsl RegNum,
    C2 = (C band (255 bsl (Quantity + RegNum) bor ones(RegNum))) bor Val2,
    {ok, [#response{socket = Socket, response = Resp}], S#s{coils = C2}};

message(#read_coils{reg_num = _RegNum, response = Resp}, Socket, #s{coils = Values} = S) ->
    {ok, [#response{socket = Socket, response = <<Resp/binary, Values>>}], S};

message(#write_hreg{response = Resp}, Socket, S) ->
    {ok, [#error_response{error_code = 2, response = Resp, socket = Socket}], S};

message(#write_hregs{response = Resp}, Socket, S) ->
    {ok, [#error_response{error_code = 2, response = Resp, socket = Socket}], S};

message(#read_hregs{response = Resp}, Socket, S) ->
    {ok, [#error_response{error_code = 2, response = Resp, socket = Socket}], S};

message(#read_iregs{response = Resp}, Socket, S) ->
    {ok, [#error_response{error_code = 2, response = Resp, socket = Socket}], S};

message(#read_inputs{response = Resp}, Socket, S) ->
    {ok, [#error_response{error_code = 2, response = Resp, socket = Socket}], S};

message(#undefined_code{response = Resp}, Socket, S) ->
    {ok, [#error_response{error_code = 3, response = Resp, socket = Socket}], S}.

%%% ---------------------------------------------------------------------------
%%% @doc handle_call(get_status, ...) return state list of coils [1, 2, 3, 4,
%%% 5].
%%% @enddoc
%%% ---------------------------------------------------------------------------
handle_call(get_status, _From, S) ->
    Stat = S#s.coils,
    {reply, Stat, [], S};

handle_call(Msg, _From, S) ->
    {reply, Msg, [], S}.

%%% ---------------------------------------------------------------------------
%%% @doc change alarm coil.
%%% @end
%%% ---------------------------------------------------------------------------
handle_cast({alarm, on, Num}, #s{coils = C} = S) ->
    C2 = C bor (1 bsl (Num - 1)),
    {noreply, [], S#s{coils = C2}};

handle_cast({alarm, off, Num}, #s{coils = C} = S) ->
    C2 = C band (bnot (1 bsl (Num - 1))),
    {noreply, [], S#s{coils = C2}};

%%% ---------------------------------------------------------------------------
%%% @doc receive unknown cast.
%%% @end
%%% ---------------------------------------------------------------------------
handle_cast(Request, S) ->
    io:format("Alarm panel receive unknown call request ~w.~n", [Request]),
    {noreply, [], S}.

%%% ---------------------------------------------------------------------------
%%% @doc
%%% ---------------------------------------------------------------------------
handle_continue(_Info, S) ->
    {noreply, [], S}.

%%% ---------------------------------------------------------------------------
%%% @doc
%%% ---------------------------------------------------------------------------
handle_info(_Info, S) ->
    {noreply, [], S}.

%%% ---------------------------------------------------------------------------
%%% @doc this calls when gen_slave terminated.
%%% @enddoc
%%% ---------------------------------------------------------------------------
terminate(Reason, S) ->
    io:format("Alarm panel terminated, reason: ~w, S: ~w.~n", [Reason, S]),
    ok.

%%% ---------------------------------------------------------------------------
%%% @doc ones(Val) => puts Val ones for bit operation.
%%% @enddoc
%%% ---------------------------------------------------------------------------
ones(0) -> 0;
ones(1) -> 1;
ones(2) -> 3;
ones(3) -> 7;
ones(4) -> 15;
ones(5) -> 31;
ones(6) -> 63;
ones(7) -> 127;
ones(8) -> 255.