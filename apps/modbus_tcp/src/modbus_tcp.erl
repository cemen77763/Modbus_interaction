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


-record(connect, {
    ip_addr :: tuple(),
    port :: integer()}).

-record(change_sock_opts, {
    active :: boolean(),
    reuseaddr :: boolean(),
    nodelay :: boolean(),
    ifaddr :: inet | local | inet6
}).

-record(disconnect, {
    reason :: atom() | term()
}).

-record(read_holding_registers, {
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: list()
}).

init([]) ->
    ChangeSopts = #change_sock_opts{active = false, reuseaddr = true, nodelay = true, ifaddr = inet},
    Connect = #connect{ip_addr = "localhost", port = 502},
    Disconnect = #disconnect{reason = normal},
    {ok, [ChangeSopts, Connect, Disconnect], 5, {continue, read_hreg}}.

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
    {ok, [], State}.

message(#read_holding_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    registers_value = LData
    }, State) ->
    io:format("Reading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n", [Dev_num, Reg_num, LData]),
    {noreply, [], State}.

handle_call(Request, _From, State) ->
    {reply, Request, [], State}.

handle_continue(read_hreg, State) ->
    ReadHreg = #read_holding_registers{
        device_number = 1,
        register_number = 2,
        quantity = 3},
    {noreply, [ReadHreg], State}.

handle_info(_Info, State) ->
    {noreply, [], State, 5}.

handle_cast(_Request, State) ->
    {noreply, [], State}.

terminate(Reason, State) ->
    io:format("Terminating reaason: ~w, state: ~w~n", [Reason, State]),
    ok.
