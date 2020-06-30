
-module(modbus_gen_server).

-behavior(gen_server).

-include("gen_server.hrl").
-include("modbus_functional_codes.hrl").

-export([start_link/0,
         init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, modbus).

-define(PORT, 502).

-define(IP_ADDR, "localhost").

-define(SOCK_OPTS, [binary, 
                    {active, true},
                    {packet, raw},
                    {reuseaddr, true},
                    {nodelay, true}]).


start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).


init([]) ->
    State = #state{ip_addr = ?IP_ADDR, port = 502},

    case {_, Socket} = gen_tcp:connect(State#state.ip_addr, State#state.port, ?SOCK_OPTS) of
        {ok, _} -> 
            io:format("Connection fine...~n"),
            {ok, State#state{socket = Socket}};
        {error, Reason} -> 
            error_logger:error_msg("~w: connection failed because ~w~n", [?MODULE, Reason]),
            erlang:send(self(), socket_connect_error),
            {ok, State}
    end.


handle_call({readH, [Device_num, Reg_num]}, _From, State) ->

    % Modbus код функции 03 (чтение Holding reg)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_HREGS:8, Reg_num:16, 1:16>>) of

        ok -> 
            io:format("Trying read device #~w, holding register #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read holding register because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({readsH, [Device_num, Reg_num, Quantity]}, _From, State) ->

    % Modbus код функции 03 (чтение нескольких Holding regs)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 6:16, Device_num:8,
                    ?FUN_CODE_READ_HREGS:8, Reg_num:16, Quantity:16>>) of
                
        ok ->
            io:format("Trying read ~w Holding registers in device #~w~n", [Quantity, Device_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read holding registers because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({writeH, [Device_num, Reg_num, Var]}, _From, State) ->

    % Modbus код функции 06 (запись Holding regs)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 6:16, Device_num:8,
                ?FUN_CODE_WRITE_HREG:8, Reg_num:16, Var:16>>) of
                
        ok ->
            io:format("Trying rewrire device #~w, Holding registers #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't write holding register because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({writesH, [Device_num, Reg_num, Values]}, _From, State) ->

    % Modbus код функции 10 (запись нескольких Holding regs)
    Reg_quantity = length(Values),
    Len = Reg_quantity * 2,

    Packet_without_values = <<1:16, 0:16, 16#0B:16, Device_num:8,
                            ?FUN_CODE_WRITE_HREGS:8, Reg_num:16, Reg_quantity:16, Len:8>>,
    PacketMsg = bin_conversion:list_to_bin16(Values, Packet_without_values),

    case gen_tcp:send(State#state.socket, PacketMsg) of
                
        ok ->
            io:format("Trying rewrire device #~w, Holding register #~w, values: ~w~n", [Device_num, Reg_num, Values]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't write holding registers because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({readI, [Device_num, Reg_num]}, _From, State) ->

    % Modbus код функции 04 (чтение Input reg)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_IREGS:8, Reg_num:16, 1:16>>) of

        ok -> 
            io:format("Trying read device #~w, Input register #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input register because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({readsI, [Device_num, Reg_num, Quantity]}, _From, State) ->

    % Modbus код функции 04 (чтение нескольких Input regs)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 6:16, Device_num:8,
                            ?FUN_CODE_READ_IREGS:8, Reg_num:16, Quantity:16>>) of

        ok -> 
            io:format("Trying read ~w Input registers in device #~w~n", [Quantity, Device_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input registers because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({writeC, [Device_num, Reg_num, Value]}, _From, State) ->

    % Modbus код функции 05 (запись Coil status)
    Var = 
        case Value of
            0 -> <<0:16>>;
            1 -> <<16#FF:8, 0:8>>;
            _ ->
                error_logger:error_msg("Wrong value ~w~n", [Value]),
                    {error, wrong_value}
        end,

    if Var =/= {error, wrong_value} -> 
        case gen_tcp:send(State#state.socket, <<1:16, 0:16, 6:16, Device_num:8,
                                ?FUN_CODE_WRITE_COIL:8, Reg_num:16, Var:16>>) of
                    
            ok ->
                io:format("Trying write ~w Coil status in device #~w~n", [Var, Device_num]),
                {reply, ok, State};

            {error, Reason} -> 
                error_logger:error_msg("Can't read Coil status because ~w~n", [Reason]),
                gen_tcp:close(State#state.socket),
                erlang:send(self(), socket_connect_error),
                {reply, error, State}

        end
    end;

handle_call({readC, [Device_num, Reg_num]}, _From, State) ->

    % Modbus код функции 01 (чтение Coil status)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 4:16, Device_num:8,
                            ?FUN_CODE_READ_COILS:8, Reg_num:16>>) of

        ok -> 
            io:format("Trying read device #~w, Coil status #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read coil status because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end;

handle_call({readIs, [Device_num, Reg_num]}, _From, State) ->

    % Modbus код функции 02 (чтение Input status)
    case gen_tcp:send(State#state.socket, <<1:16, 0:16, 4:16, Device_num:8,
                            ?FUN_CODE_READ_INPUTS:8, Reg_num:16>>) of

        ok -> 
            io:format("Trying read device #~w, Input status #~w~n", [Device_num, Reg_num]),
            {reply, ok, State};

        {error, Reason} -> 
            error_logger:error_msg("Can't read input status because ~w~n", [Reason]),
            gen_tcp:close(State#state.socket),
            erlang:send(self(), socket_connect_error),
            {reply, error, State}

    end.




handle_cast(_, State) ->
    {noreply, State}.


handle_info(socket_connect_error, State) ->

    case {_, Socket} = gen_tcp:connect(State#state.ip_addr, State#state.port, ?SOCK_OPTS) of
        {ok, _} ->
            io:format("Connection fine...~n"),
            {noreply, State#state{socket = Socket}};
        {error, Reason} -> 
            error_logger:error_msg("~w: connection failed because ~w~n", [?MODULE, Reason]),
            erlang:send(self(), socket_connect_error),
            {noreply, State}
    end;

handle_info(_A, State) ->
    {noreply, State}.

terminate(_A, _B) ->
    ok.

code_change(_A, _B, _C) ->
    ok.