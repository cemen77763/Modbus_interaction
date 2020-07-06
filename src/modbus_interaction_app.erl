%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc This module implement interaction with devices according to the Modbus TCP protocol  %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(modbus_interaction_app).

-behaviour(application).

-export([
    start/2,
    stop/1]).
 
-define(SERVER, modbus_gen).

-define(STORAGE, storage_server).


start(_StartType, _StartArgs) ->
    modbus_interaction_sup:start_link().


stop(_State) ->
    gen_server:stop(?SERVER),
    gen_server:stop(?STORAGE),
    ok.


