%%% -----------------------------------------------------------------------------------------
%%% @doc modbus tcp slave
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_slave).

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
    start_loop/0
    ]).

start() ->
    gen_slave:start_link({local, ?SERVER}, ?MODULE, [], []).

start_loop() ->
    {ok, LSock} = gen_tcp:listen(502, ?DEFAULT_SOCK_OPTS),
    receive
        {stop, _Reason} ->
            ok
    end,
    {ok, Sock} = gen_tcp:accept(LSock),
    gen_slave:start_link({local, ?SERVER}, ?MODULE, [Sock], []),
    start_loop().
