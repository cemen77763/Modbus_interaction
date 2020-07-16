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
    ChangeSopts = #change_sock_opts{active = false, reuseaddr = true, nodelay = true, ifaddr = inet},
    Connect = #connect{ip_addr = "localhost", port = 5000},
    {ok, [ChangeSopts, Connect], 5, {continue, read}}.

connect(#socket_info{ip_addr = Ip_addr, port = Port}, State) ->
    io:format("Connection fine Ip addr: ~w Port ~w~n", [Ip_addr, Port]),
    {ok, [], State}.

disconnect(Reason, State) ->
    io:format("Disconected because ~w.~n", [Reason]),
    _Connect = #connect{ip_addr = "localhost", port = 5000},
    {ok, [], State}.

message(#read_holding_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    registers_value = LData
    }, State) ->
    io:format("~nReading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n~n", [Dev_num, Reg_num, LData]),
    {ok, [], State};

message(#read_input_registers{
    device_number = Dev_num,
    register_number = Reg_num,
    registers_value = LData
    }, State) ->
    io:format("~nReading holding registers~ndevice: ~w~nfirst register:~w~ndata: ~w~n~n", [Dev_num, Reg_num, LData]),
    {ok, [], State};    

message(_RegInfo, State) ->
    {ok, [], State}.

handle_call(Request, _From, State) ->
    {reply, Request, [], State}.

handle_continue(read, State) ->
    ReadHreg = #read_holding_registers{
        device_number = 1,
        register_number = 1,
        quantity = 4},
    ReadIreg = #read_input_registers{
        device_number = 1,
        register_number = 1,
        quantity = 2},
    ReadCoil = #read_coils_status{
        device_number = 1,
        register_number = 1,
        quantity = 1},
    ReadInput = #read_inputs_status{
        device_number = 1,
        register_number = 2,
        quantity = 3},
    gen_modbus:cast(?SERVER, write),
    {noreply, [ReadHreg, ReadIreg, ReadCoil, ReadInput], State}.

handle_info(_Info, State) ->
    {noreply, [], State}.

handle_cast(write, State) ->
    WriteHreg = #write_holding_register{
        device_number = 1,
        register_number = 1,
        register_value = 15
        },
    WriteHregs = #write_holding_registers{
        device_number = 1,
        register_number = 1,
        registers_value = [13, 15]},
    WriteCoil = #write_coil_status{
        device_number = 1,
        register_number = 1,
        register_value = 0},
    WriteCoils = #write_coils_status{
        device_number = 1,
        register_number = 1,
        quantity = 4,
        registers_value = 2#00001111},
    Disconnect = #disconnect{reason = normal},
    {noreply, [WriteHreg, WriteHregs, WriteCoil, WriteCoils, Disconnect], State};

handle_cast(_Request, State) ->
    {noreply, [], State}.

terminate(Reason, State) ->
    io:format("Terminating reason: ~w, state: ~w~n", [Reason, State]),
    ok.
