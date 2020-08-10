%%% -----------------------------------------------------------------------------------------
%%% @doc Modbus TCP application and supervisor
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_master_app).

-behaviour(application).

-behaviour(supervisor).

%% application callbacks
-export([
    start/2,
    stop/1]).

%% supervisor callbacks
-export([
    init/1]).

-define(MASTER, modbus_master).

start(_StartType, _StartArgs) ->
    start_link().

stop(_State) ->
    gen_modbus_m:stop(?MASTER).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

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
    ChildSpecs = [
        #{
        id => ?MASTER,
        start => {?MASTER, start, []},
        restart => permanent,
        shutdown => 1000,
        type => worker,
        modules => [?MASTER]}
        ],
    {ok, {SupFlags, ChildSpecs}}.



