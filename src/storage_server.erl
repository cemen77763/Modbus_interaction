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

-define(SERVER, ?MODULE).


start_link() ->     
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


init([]) ->
    S = dict:new(),
    {ok, S}.


handle_call({#read_hreg{device_num = Dev_num}, Data}, _From, S) ->
    error_logger:info_msg("Data in device #~w in single holding register is  ~w~n", [Dev_num, Data]),
    {reply, ok, dict:append(read_hreg, {device_num, Data}, S)};

handle_call({#write_hreg{device_num = Dev_num}, Var}, _From, S) ->
    error_logger:info_msg("~w recorded in device #~w in single holding register~n", [Var, Dev_num]),
    {reply, ok, dict:append(write_hreg, {device_num, Var}, S)};

handle_call({#write_hregs{device_num = Dev_num}, Quantity}, _From, S) ->
    error_logger:info_msg("~w values recorded in device #~w in multiple holding registers~n", [Quantity, Dev_num]),
    {reply, ok, dict:append(write_hregs, {device_num, Quantity}, S)};

handle_call({#read_hregs{device_num = Dev_num}, Data}, _From, S) ->
    error_logger:info_msg("Data in device #~w in multiple holding registers is  ~w~n", [Dev_num, Data]),
    {reply, ok, dict:append(read_hregs, {device_num, Data}, S)};

handle_call({#read_ireg{device_num = Dev_num}, Data}, _From, S) ->
    error_logger:info_msg("Data in device #~w in single input register is  ~w~n", [Dev_num, Data]),
    {reply, ok, dict:append(read_ireg, {device_num, Data}, S)};

handle_call({#read_iregs{device_num = Dev_num}, Data}, _From, S) ->
    error_logger:info_msg("Data in device #~w in multiple input registers is  ~w~n", [Dev_num, Data]),
    {reply, ok, dict:append(read_iregs, {device_num, Data}, S)};

handle_call({#read_coil{device_num = Dev_num}, Data}, _From, S) ->
    error_logger:info_msg("Data in device #~w in coil status is  ~w~n", [Dev_num, Data]),
    {reply, ok, dict:append(read_coil, {device_num, Data}, S)};

handle_call({#read_inputs{device_num = Dev_num}, Data}, _From, S) ->
    error_logger:info_msg("Data in device #~w in input status is  ~w~n", [Dev_num, Data]),
    {reply, ok, dict:append(read_ireg, {device_num, Data}, S)};

handle_call({#write_coil{device_num = Dev_num}, Var}, _From, S) ->
    error_logger:info_msg("~w recorded in device #~w in coil status~n", [Var, Dev_num]),
    {reply, ok, dict:append(write_coil, {device_num, Var}, S)};

handle_call(Msg, _From, S) ->
    error_logger:error_msg("Got unknown message ~w~n.", [Msg]),
    {reply, unknown, S}.


handle_cast(Msg, S) ->
    error_logger:error_msg("Got unknown message ~w~n.", [Msg]),
    {noreply, S}.


handle_info(Msg, S) ->
    error_logger:error_msg("Got unknown message ~w~n.", [Msg]),
    {noreply, S}.


terminate(_Reason, _S) ->
    ok.


code_change(_OldVsn, S, _Extra) ->
    {ok, S}.