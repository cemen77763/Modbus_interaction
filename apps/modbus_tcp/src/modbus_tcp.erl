%%% -----------------------------------------------------------------------------------------
%%% @doc Interaction with modbus TCP devices using gen_modbus behaviour
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(modbus_tcp).

-behaviour(gen_modbus).

-include_lib("../../gen_modbus/include/gen_modbus.hrl").

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

-define(SERVER, gen_modbus).

start() ->
    gen_modbus:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_modbus:stop(?SERVER).

init([]) ->
    ChangeSopts = #change_sock_opts{reuseaddr = true, nodelay = true},
    Connect = #connect{ip_addr = "localhost", port = 5000},
    {ok, [ChangeSopts, Connect], 5}.

connect(#sock_info{ip_addr = Ip_addr, port = Port}, State) ->
    WriteHreg = #write_holding_register{
        device_number = 2,
        register_number = 1,
        register_value = 12
        },
    io:format("Connection fine Ip addr: ~w Port ~w~n", [Ip_addr, Port]),
    {ok, [WriteHreg], State};

connect(_sock_info, State) ->
    {ok, [], State}.

disconnect(Reason, State) ->
    io:format("Disconected because ~w.~n", [Reason]),
    _Connect = #connect{ip_addr = "localhost", port = 5000},
    _Disconnect = #disconnect{reason = normal},
    {ok, [], State}.

message(#read_register{type = holding, device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, State) ->
    ReadIreg = #read_register{
        type = input,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    io:format("~nReading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [ReadIreg], State};

message(#read_register{type = input, device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, State) ->
    ReadCoils = #read_status{
        type = coil,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    io:format("~nReading input registers~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [ReadCoils], State};

message(#read_status{type = coil, device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, State) ->
    ReadInput = #read_status{
        type = input,
        device_number = 2,
        register_number = 12,
        quantity = 5},
    io:format("~nReading coils status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [ReadInput], State};

message(#read_status{type = input, device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, State) ->
    Disconnect = #disconnect{reason = normal},
    io:format("~nReading inputs status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [Disconnect], State};

message(#write_holding_register{device_number = Dev_num, register_number = Reg_num, register_value = Ldata}, State) ->
    WriteHregs = #write_holding_registers{
        device_number = 2,
        register_number = 2,
        registers_value = [13, 14, 15, 16]},
    io:format("~nWriting holding register~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [WriteHregs], State};

message(#write_holding_registers{device_number = Dev_num, register_number = Reg_num, registers_value = Ldata}, State) ->
    WriteCoil = #write_coil_status{
        device_number = 2,
        register_number = 1,
        register_value = 1},
    io:format("~nWriting holding registers~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Ldata]),
    {ok, [WriteCoil], State};

message(#write_coil_status{device_number = Dev_num, register_number = Reg_num, register_value = Data}, State) ->
    WriteCoils = #write_coils_status{
        device_number = 2,
        register_number = 2,
        quantity = 4,
        registers_value = 2#1010},
    io:format("~nWriting coil status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Data]),
    {ok, [WriteCoils], State};

message(#write_coils_status{device_number = Dev_num, register_number = Reg_num, quantity = _Quantity, registers_value = Bdata}, State) ->
    ReadHreg = #read_register{
        type = holding,
        device_number = 2,
        register_number = 1,
        quantity = 5},
    io:format("~nWriting coils status~ndevice: ~w~nfirst register: ~w~ndata: ~w~n~n", [Dev_num, Reg_num, Bdata]),
    {ok, [ReadHreg], State};

message(_RegInfo, State) ->
    {ok, [], State}.

handle_call(Request, _From, State) ->
    {reply, Request, [], State}.

handle_continue(_Info, State) ->
    {noreply, [], State}.

handle_info(_Info, State) ->
    {noreply, [], State}.

handle_cast(write, State) ->
    {noreply, [], State};

handle_cast(_Request, State) ->
    {noreply, [], State}.

terminate(Reason, State) ->
    io:format("Terminating reason: ~w, state: ~w~n", [Reason, State]),
    ok.
