-module(modbus_tcp).

-behaviour(gen_modbus).

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

read_hreg(Dev_num, Reg_num) ->
    gen_modbus:read_register(?SERVER, {holding_register, Dev_num, Reg_num}).

write_hreg(Dev_num, Reg_num, Values) ->
    gen_modbus:write_register(?SERVER, {holding_register, Dev_num, Reg_num, Values}).

read_hregs(Dev_num, Reg_num, Quantity) ->
    gen_modbus:read_register(?SERVER, {holding_register, Dev_num, Reg_num, Quantity}).

read_iregs(Dev_num, Reg_num, Quantity) ->
    gen_modbus:read_register(?SERVER, {input_register, Dev_num, Reg_num, Quantity}).

read_creg(Dev_num, Reg_num) ->
    gen_modbus:read_register(?SERVER, {coil_status, Dev_num, Reg_num}).

init([]) ->
    {ok, 5}.

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

disconnect(State, _Reason) ->
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
        
        {coils_status, Dev_num, Reg_num, Data} ->
            io:format("Device number is ~w, first register number is ~w, register values is ~w.~n", [Dev_num, Reg_num, Data]);

        
        {error, Reason} ->
            io:format("Error: ~w~n", [Reason])

    end,
    {noreply, State}.

handle_call(_Request, _From, _State) ->
    ok.

handle_continue(_Info, _State) ->
    ok.

handle_info(_Info, _State) ->
    ok.

handle_cast(_Request, _State) ->
    ok.

terminate(_Reason, _State) ->
    io:format("terminating~n"),
    ok.
