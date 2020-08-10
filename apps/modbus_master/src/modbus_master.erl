%%% -----------------------------------------------------------------------------------------
%%% @doc Interaction with modbus TCP devices using gen_modbus behaviour
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_master).

-behaviour(gen_modbus_m).

-include_lib("gen_modbus_m/include/gen_modbus_m.hrl").

-define(IP_ADDR, "localhost").

-define(PORT, 5000).

-export([
    start/0,
    stop/0,
    test_registers/0
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
    terminate/2
    ]).

%%% ---------------------------------------------------------------------------
%%% @doc start gen_modbus_m.
%%% @end
%%% ---------------------------------------------------------------------------
start() ->
    gen_modbus_m:start_link({local, ?MODULE}, ?MODULE, [], []).

%%% ---------------------------------------------------------------------------
%%% @doc stop gen_modbus_m.
%%% @end
%%% ---------------------------------------------------------------------------
stop() ->
    gen_modbus_m:stop(?MODULE).

%%% ---------------------------------------------------------------------------
%%% @doc test all modbus registers(input regs, holding regs, coils, inputs)
%%% in slave device.
%%% @end
%%% ---------------------------------------------------------------------------
test_registers() ->
    gen_modbus_m:call(?MODULE, {test_registers}).

%%% ---------------------------------------------------------------------------
%%% @doc Connect to IP_ADDR and PORT in init.
%%% @end
%%% ---------------------------------------------------------------------------
init([]) ->
    ChangeSopts = #change_sock_opts{reuseaddr = true, nodelay = true},
    Connect = #connect{ip_addr = ?IP_ADDR, port = ?PORT},
    {ok, [ChangeSopts, Connect], 5}.

%%% ---------------------------------------------------------------------------
%%% @doc called when connected to modbus tcp slave device.
%%% @end
%%% ---------------------------------------------------------------------------
connect(#sock_info{socket = _Sock, ip_addr = Ip_addr, port = Port}, S) ->
    error_logger:info_msg("Connection fine Ip addr: ~w Port ~w~n", [Ip_addr, Port]),
    {ok, [], S}.

%%% ---------------------------------------------------------------------------
%%% @doc called when disconnected from modbus tcp slave device.
%%% @end
%%% ---------------------------------------------------------------------------
disconnect(_Reason, S) ->
    Connect = #connect{ip_addr = ?IP_ADDR, port = ?PORT},
    {ok, [Connect], S}.

%%% ---------------------------------------------------------------------------
%%% @doc test read and write  all registers.
%%% @end
%%% ---------------------------------------------------------------------------
message(#read_register{type = holding, device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, S) ->
    ReadIreg = #read_register{
        transaction_id = 1,
        type = input,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    error_logger:info_msg("~nReading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [ReadIreg], S};

message(#read_register{type = input, device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, S) ->
    ReadCoils = #read_status{
        transaction_id = 1,
        type = coil,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    error_logger:info_msg("~nReading input registers~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [ReadCoils], S};

message(#read_status{type = coil, device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, S) ->
    ReadInput = #read_status{
        transaction_id = 1,
        type = input,
        device_number = 2,
        register_number = 12,
        quantity = 5},
    _Disconnect = #disconnect{reason = normal},
    error_logger:info_msg("~nReading coils status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [ReadInput], S};

message(#read_status{type = input, device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, S) ->
    _Disconnect = #disconnect{reason = normal},
    error_logger:info_msg("~nReading inputs status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [], S};

message(#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Ldata}, S) ->
    WriteHregs = #write_holding_registers{
        transaction_id = 1,
        device_number = 2,
        register_number = 2,
        registers_value = [13, 14, 15, 16]},
    error_logger:info_msg("~nWriting holding register~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [WriteHregs], S};

message(#write_holding_registers{device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 0,
        register_value = 1},
    error_logger:info_msg("~nWriting holding registers~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [WriteCoil], S};

message(#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Data}, S) ->
    WriteCoils = #write_coils_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 1,
        quantity = 4,
        registers_value = 2#0101},
    error_logger:info_msg("~nWriting coil status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Data]),
    {ok, [WriteCoils], S};

message(#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, S) ->
    ReadHreg = #read_register{
        transaction_id = 1,
        type = holding,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    error_logger:info_msg("~nWriting coils status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [ReadHreg], S};

message(_RegInfo, S) ->
    {ok, [], S}.


%%% ---------------------------------------------------------------------------
%%% @doc set coil in alarm panel.
%%% @end
%%% ---------------------------------------------------------------------------
handle_call({test_registers}, _From, S) ->
    WriteHreg = #write_holding_register{
        transaction_id = 1,
        device_number = 2,
        register_number = 1,
        register_value = 12
        },
    {reply, ok, [WriteHreg], S};

%%% ---------------------------------------------------------------------------
%%% @doc handles like in gen_server.
%%% @end
%%% ---------------------------------------------------------------------------
handle_call(Request, _From, S) ->
    error_logger:info_msg("Request is ~w~n", [Request]),
    {reply, Request, [], S}.

handle_continue(_Info, S) ->
    {noreply, [], S}.

handle_info(_Info, S) ->
    {noreply, [], S}.

handle_cast(_Request, S) ->
    {noreply, [], S}.

%%% ---------------------------------------------------------------------------
%%% @doc terminate calls when gen_modbus_m stopped.
%%% @end
%%% ---------------------------------------------------------------------------
terminate(Reason, S) ->
    error_logger:info_msg("Terminating reason: ~w, S: ~w~n", [Reason, S]),
    ok.
