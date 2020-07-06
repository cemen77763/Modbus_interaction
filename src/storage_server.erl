%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc Server for storage inforamation about Modbus TCP device registers                    %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(storage_server).

-behaviour(gen_server).

-include("modbus_functional_codes.hrl").

-export([
    start_link/0,
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, storage_server).


start_link() ->     
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


init([]) ->
    S = dict:new(),
    {ok, S}.


handle_call(_, _From, S) ->
    error_logger:error_msg("Got unknown message~n."),
    {reply, ok, S}.


handle_cast(_Msg, S) ->
    error_logger:error_msg("Got unknown message~n."),
    {noreply, S}.


handle_info(Msg, S) ->
    error_logger:error_msg("Got unknown message ~w~n.", [Msg]),
    {noreply, S}.


terminate(_Reason, _S) ->
    ok.


code_change(_OldVsn, S, _Extra) ->
    {ok, S}.