%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc This module implement interaction with devices according to the Modbus TCP protocol  %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(modbus_interaction_app).

-behaviour(application).

-export([start/2,
        start_link/0,
        stop/1]).
 
-define(SERVER, modbus_gen).


start_link() ->
    modbus_interaction_sup:start_link().


start(_StartType, _StartArgs) ->
    modbus_gen_server:start_link(),
    modbus_interaction_sup:start_link().


stop(_State) ->
    gen_server:stop(?SERVER),
    ok.


