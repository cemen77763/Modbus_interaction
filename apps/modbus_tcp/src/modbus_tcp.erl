-module(modbus_tcp).

-behaviour(gen_modbus).

-include("../../gen_modbus/include/gen_modbus.hrl").

-export([
    start/0,
    stop/0,
    connect_to/1,
    disconnect_from/0
    ]).

% gen_modbus callbacks
-export([
    init/1,
    connect/2,
    handle_call/3,
    handle_continue/2,
    handle_info/2,
    handle_cast/2,
    disconnect/2,
    message/2,
    terminate/2]).

-define(SERVER, gen_modbus).

start() ->
    gen_modbus:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_modbus:stop(?SERVER).

connect_to([Ip_addr, Port]) ->
    gen_modbus:try_connect(?SERVER, [Ip_addr, Port]).

disconnect_from() ->
    gen_modbus:try_disconnect(?SERVER).

init([]) ->
    ChangeSopts = #change_sock_opts{active = false, reuseaddr = true, nodelay = true, ifaddr = inet},
    Connect = #connect{ip_addr = "localhost", port = 5000},
    {ok, [ChangeSopts, Connect], 5, {continue, read_hreg}}.

connect(State, Info) ->
    case Info of
        {connected, Ip_addr, Port} ->
            io:format("connected to ~w ~w~n", [Ip_addr, Port]);
        Info ->
            io:format("connected fine~n")
    end,
    {ok, [], State}.

disconnect(Reason, State) ->
    io:format("Disconected because ~w.~n", [Reason]),
    Connect = #connect{ip_addr = "localhost", port = 5000},
    {ok, [Connect], State}.

message(#read_holding_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    registers_value = LData
    }, State) ->
    io:format("Reading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n", [Dev_num, Reg_num, LData]),
    {ok, [], State};

message(_RegInfo, State) ->
    {ok, [], State}.

handle_call(Request, _From, State) ->
    {reply, Request, [], State}.

handle_continue(read_hreg, State) ->
    ReadHreg = #read_holding_registers{
        device_number = 1,
        register_number = 2,
        quantity = 3},
    ReadIreg = #read_input_registers{
        device_number = 1,
        register_number = 2,
        quantity = 3},
    _Disconnect = #disconnect{reason = normal},
    {noreply, [ReadHreg, ReadIreg], State}.

handle_info(_Info, State) ->
    {noreply, [], State, 5}.

handle_cast(_Request, State) ->
    {noreply, [], State}.

terminate(Reason, State) ->
    io:format("Terminating reaason: ~w, state: ~w~n", [Reason, State]),
    ok.
