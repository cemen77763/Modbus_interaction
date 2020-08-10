%%% -----------------------------------------------------------------------------------------
%%% @doc Modbus TCP application and supervisor
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(alarm_panel_app).

-behaviour(application).

-behaviour(supervisor).

%% application callbacks
-export([
    start/2,
    stop/1]).

%% supervisor callbacks
-export([
    init/1]).

-define(PANEL, alarm_panel).

start(_StartType, _StartArgs) ->
    start_link().

stop(_State) ->
    gen_modbus_s:stop(?PANEL).

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
        strategy => one_for_one,
        intensity => 3,
        period => 1000},
    ChildSpecs = [
        #{
        id => ?PANEL,
        start => {?PANEL, start, []},
        restart => permanent,
        shutdown => 1000,
        type => worker,
        modules => [?PANEL]
        }],
    {ok, {SupFlags, ChildSpecs}}.



