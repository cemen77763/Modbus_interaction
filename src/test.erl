-module(test).

-behaviour(modbusTCP).

-export([
    start/0,
    stop/0,
    init_modbus/1,
    connect/1,
    disconnect/1,
    connect_to/1,
    disconnect_from/0,
    message/2,
    read_hreg/2]).

start() ->
    modbusTCP:start_link({local, tcp}, ?MODULE, [], []).

stop() ->
    modbusTCP:stop(tcp).

connect_to([Ip_addr, Port]) ->
    modbusTCP:try_connect(tcp, [Ip_addr, Port]).

disconnect_from() ->
    modbusTCP:try_disconnect(tcp).

read_hreg(Dev_num, Reg_num) ->
    modbusTCP:read_register(tcp, {holding_register, Dev_num, Reg_num}).

init_modbus([]) ->
    {ok, 5, ["localhost", 502]}.

connect(State) ->
    {ok, State, ["localhost", 502]}.

disconnect(State) ->
    {ok, State}.

message(RegisterInfo, State) ->
    case RegisterInfo of
        [Dev_num, Reg_num, Reg_value] ->
            io:format("Device number is ~w, register number is ~w, register value is ~w.~n", [Dev_num, Reg_num, Reg_value]);
        
        [error, Reason] ->
            io:format("Error: ~w~n", [Reason])

    end,
    {noreply, State}.
