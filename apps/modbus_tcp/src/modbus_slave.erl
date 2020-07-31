%%% -----------------------------------------------------------------------------------------
%%% @doc modbus tcp slave
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_slave).

-behaviour(gen_slave).

-include("../../gen_modbus/include/gen_slave.hrl").

-define(DEFAULT_DEVICE_NUM, 2).

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, true},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(s, {
    allowed_connections :: integer()
    }).

-define(SERVER, gen_slave).

-define(PORT, 5000).

-export([
    start/0,
    stop/0
    ]).

-export([
    init/1,
    connect/2,
    handle_call/3,
    handle_continue/2,
    handle_info/2,
    handle_cast/2,
    disconnect/3,
    message/2,
    terminate/2
    ]).

start() ->
    gen_slave:start_link({local, ?SERVER}, ?MODULE, [?PORT, ?DEFAULT_DEVICE_NUM], []).

stop() ->
    gen_slave:stop(?SERVER).

init([]) ->
    {ok, [wait_connect], #s{allowed_connections = 5}}.

connect(Socket, #s{allowed_connections = Connections} = S) ->
    case (Connections - 1) =/= 0 of
        true ->
            io:format("Connected to ~w...~n", [Socket]),
            {ok, [], S#s{allowed_connections = Connections - 1}};
        _ ->
            io:format("Connections limit reached~n")
    end.

disconnect(Socket, Reason, #s{allowed_connections = Connections} = S) ->
    io:format("Disconected because ~w from ~w.~n", [Reason, Socket]),
    {ok, [wait_connect], S#s{allowed_connections = Connections + 1}}.

message(RegInfo, S) ->
    io:format("Reg info is ~w~n", [RegInfo]),
    {ok, [], S}.

handle_call(Msg, _From, S) ->
    io:format("Handle call ~w.~n", [Msg]),
    {reply, Msg, [], S}.

handle_cast({alarm, on, 1}, S) ->
    Alarm = #alarm{type = 1, status = on},
    {noreply, [Alarm], S};

handle_cast({alarm, on, 2}, S) ->
    Alarm = #alarm{type = 2, status = on},
    {noreply, [Alarm], S};

handle_cast({alarm, on, 3}, S) ->
    Alarm = #alarm{type = 3, status = on},
    {noreply, [Alarm], S};

handle_cast({alarm, on, 4}, S) ->
    Alarm = #alarm{type = 4, status = on},
    {noreply, [Alarm], S};

handle_cast({alarm, on, 5}, S) ->
    Alarm = #alarm{type = 5, status = on},
    {noreply, [Alarm], S};

handle_cast({alarm, off, 1}, S) ->
    Alarm = #alarm{type = 1, status = off},
    {noreply, [Alarm], S};

handle_cast({alarm, off, 2}, S) ->
    Alarm = #alarm{type = 2, status = off},
    {noreply, [Alarm], S};

handle_cast({alarm, off, 3}, S) ->
    Alarm = #alarm{type = 3, status = off},
    {noreply, [Alarm], S};

handle_cast({alarm, off, 4}, S) ->
    Alarm = #alarm{type = 4, status = off},
    {noreply, [Alarm], S};

handle_cast({alarm, off, 5}, S) ->
    Alarm = #alarm{type = 5, status = off},
    {noreply, [Alarm], S};

handle_cast(Request, S) ->
    io:format("Request is ~w~n", [Request]),
    {noreply, [], S}.

handle_continue(_Info, S) ->
    {noreply, [], S}.

handle_info(_Info, S) ->
    {noreply, [], S}.

terminate(Reason, S) ->
    io:format("Terminating reason: ~w, S: ~w~n", [Reason, S]),
    ok.
