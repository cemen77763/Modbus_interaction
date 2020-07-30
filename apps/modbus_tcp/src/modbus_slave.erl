%%% -----------------------------------------------------------------------------------------
%%% @doc modbus tcp slave
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_slave).

-behaviour(gen_slave).

-include("../../gen_modbus/include/gen_modbus.hrl").

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, true},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-define(SERVER, gen_slave).

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
    disconnect/2,
    message/2,
    terminate/2
    ]).

start() ->
    gen_slave:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_slave:stop(?SERVER).

init([]) ->
    {ok, [#wait_connect{}], 5}.

connect(_SockInfo, S) ->
    {ok, [], S}.

disconnect(Reason, S) ->
    io:format("Disconected slave because ~w.~n", [Reason]),
    {ok, [#wait_connect{}], S}.

message(_RegInfo, S) ->
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
