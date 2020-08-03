%%% -----------------------------------------------------------------------------------------
%%% @doc Interaction with modbus TCP devices using gen_modbus behaviour
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_master).

-behaviour(gen_master).

-include_lib("../../gen_modbus/include/gen_master.hrl").

-export([
    start/0,
    stop/0
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

-define(SERVER, gen_master).

start() ->
    gen_master:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_master:stop(?SERVER).

init([]) ->
    ChangeSopts = #change_sock_opts{reuseaddr = true, nodelay = true},
    Connect = #connect{ip_addr = "localhost", port = 5000},
    {ok, [ChangeSopts, Connect], 5}.

connect(#sock_info{ip_addr = Ip_addr, port = Port}, S) ->
    WriteHreg = #write_holding_register{
        transaction_id = 1,
        device_number = 2,
        register_number = 1,
        register_value = 12
        },
    io:format("Connection fine Ip addr: ~w Port ~w~n", [Ip_addr, Port]),
    {ok, [WriteHreg], S}.

disconnect(Reason, S) ->
    io:format("Disconected master because ~w.~n", [Reason]),
    _Connect = #connect{ip_addr = "localhost", port = 5000},
    _Disconnect = #disconnect{reason = normal},
    {ok, [], S}.

message(#read_register{type = holding, device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, S) ->
    ReadIreg = #read_register{
        transaction_id = 1,
        type = input,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    io:format("~nReading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [ReadIreg], S};

message(#read_register{type = input, device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, S) ->
    ReadCoils = #read_status{
        transaction_id = 1,
        type = coil,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    io:format("~nReading input registers~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [ReadCoils], S};

message(#read_status{type = coil, device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, S) ->
    ReadInput = #read_status{
        transaction_id = 1,
        type = input,
        device_number = 2,
        register_number = 12,
        quantity = 5},
    _Disconnect = #disconnect{reason = normal},
    io:format("~nReading coils status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [ReadInput], S};

message(#read_status{type = input, device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, S) ->
    Disconnect = #disconnect{reason = normal},
    io:format("~nReading inputs status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [Disconnect], S};

message(#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Ldata}, S) ->
    WriteHregs = #write_holding_registers{
        transaction_id = 1,
        device_number = 2,
        register_number = 2,
        registers_value = [13, 14, 15, 16]},
    io:format("~nWriting holding register~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [WriteHregs], S};

message(#write_holding_registers{device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 3,
        register_value = 0},
    io:format("~nWriting holding registers~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [WriteCoil], S};

message(#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Data}, S) ->
    WriteCoils = #write_coils_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 2,
        quantity = 4,
        registers_value = 2#1111},
    io:format("~nWriting coil status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Data]),
    {ok, [WriteCoils], S};

message(#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, S) ->
    ReadHreg = #read_register{
        transaction_id = 1,
        type = holding,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    io:format("~nWriting coils status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [ReadHreg], S};

message(_RegInfo, S) ->
    {ok, [], S}.

handle_call({alarm, 1}, _From, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 1,
        register_value = 1},
    {noreply, [WriteCoil], S};

handle_call({alarm, 2}, _From, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 2,
        register_value = 1},
    {noreply, [WriteCoil], S};

handle_call({alarm, 3}, _From, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 3,
        register_value = 1},
    {noreply, [WriteCoil], S};

handle_call({alarm, 4}, _From, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 4,
        register_value = 1},
    {noreply, [WriteCoil], S};


handle_call({alarm, 5}, _From, S) ->
    WriteCoil = #write_coil_status{
        transaction_id = 1,
        device_number = 2,
        register_number = 5,
        register_value = 1},
    {noreply, [WriteCoil], S};

handle_call(Request, _From, S) ->
    io:format("Request is ~w~n", [Request]),
    {reply, Request, [], S}.

handle_continue(_Info, S) ->
    {noreply, [], S}.

handle_info(_Info, S) ->
    {noreply, [], S}.

handle_cast(_Request, S) ->
    {noreply, [], S}.

terminate(Reason, S) ->
    io:format("Terminating reason: ~w, S: ~w~n", [Reason, S]),
    ok.
