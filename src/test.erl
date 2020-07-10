-module(test).

-behaviour(modbusTCP).

-export([
    start/0,
    stop/0,
    connect_to/1,
    disconnect_from/0,
    read_hreg/2,
    read_iregs/3,
    read_hregs/3,
    write_hreg/3,
    read_creg/2]).

% modbusTCP callbacks
-export([
    init_modbus/1,
    connect/2,
    disconnect/1,
    message/2,
    terminate_modbus/2]).

-define(SERVER, mtcp).

start() ->
    modbusTCP:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    modbusTCP:stop(?SERVER).

connect_to([Ip_addr, Port]) ->
    modbusTCP:try_connect(?SERVER, [Ip_addr, Port]).

disconnect_from() ->
    modbusTCP:try_disconnect(?SERVER).

read_hreg(Dev_num, Reg_num) ->
    modbusTCP:read_register(?SERVER, {holding_register, Dev_num, Reg_num}).

write_hreg(Dev_num, Reg_num, Values) ->
    modbusTCP:write_register(?SERVER, {holding_register, Dev_num, Reg_num, Values}).

read_hregs(Dev_num, Reg_num, Quantity) ->
    modbusTCP:read_register(?SERVER, {holding_register, Dev_num, Reg_num, Quantity}).

read_iregs(Dev_num, Reg_num, Quantity) ->
    modbusTCP:read_register(?SERVER, {input_register, Dev_num, Reg_num, Quantity}).

read_creg(Dev_num, Reg_num) ->
    modbusTCP:read_register(?SERVER, {coil_status, Dev_num, Reg_num}).

init_modbus([]) ->
    {ok, 5, ["localhost", 502]}.

connect(State, Info) ->
    case Info of
        {error, Reason} ->
            io:format("Error: ~w~n", [Reason]);
        {connected, Ip_addr, Port} ->
            io:format("connected to ~w ~w~n", [Ip_addr, Port]);
        Info ->
            io:format("connected fine~n")
    end,
    {ok, State, 0}.

disconnect(State) ->
    io:format("Disconect was fine.~n"),
    {ok, State}.

message(RegisterInfo, State) ->
    case RegisterInfo of
        {holding_register, Dev_num, Reg_num, LData} when is_list(LData) ->
            io:format("Device number is ~w, first register number is ~w, register values is ~w.~n", [Dev_num, Reg_num, LData]);

        {holding_register, Dev_num, Reg_num, Reg_value} ->
            io:format("Device number is ~w, register number is ~w, register value is ~w.~n", [Dev_num, Reg_num, Reg_value]);

        {holding_register, Dev_num, Reg_num, Values, _Quantity} ->
            io:format("Device number is ~w, register number is ~w, register values is ~w.~n", [Dev_num, Reg_num, Values]);

        {input_register, Dev_num, Reg_num, LData} when is_list(LData) ->
            io:format("Device number is ~w, first register number is ~w, register values is ~w.~n", [Dev_num, Reg_num, LData]);
        
        {coil_status, Dev_num, Reg_num, Data} ->
            io:format("Device number is ~w, first register number is ~w, register values is ~w.~n", [Dev_num, Reg_num, Data]);

        
        {error, Reason} ->
            io:format("Error: ~w~n", [Reason])

    end,
    {noreply, State}.

terminate_modbus(_Reason, _State) ->
    io:format("terminating~n"),
    ok.
