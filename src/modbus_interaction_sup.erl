%%%-------------------------------------------------------------------%%%
%%% @doc modbus_interaction top level supervisor                      %%%
%%% @end                                                              %%%
%%%-------------------------------------------------------------------%%%

-module(modbus_interaction_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(SERVER, ?MODULE).


start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).


%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional


init([]) ->
    SupFlags = #{
        strategy => one_for_all,
        intensity => 3,
        period => 1000},

    ChildSpecs = [#{
        id => modbus,
        start => {modbus_gen_server, start_link, []},
        restart => permanent,
        shutdown => 1000,
        type => worker,
        modules => []},

        #{id => modbus_storage,
        start => {storage_server, start_link, []},
        restart => permanent,
        shutdown => 1000,
        type => worker,
        modules => []}],

    {ok, {SupFlags, ChildSpecs}}.
