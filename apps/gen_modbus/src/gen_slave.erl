%%% -----------------------------------------------------------------------------------------
%%% @doc Slave modbus TCP device behaviour
%%% @end
%%% -----------------------------------------------------------------------------------------
-module(gen_slave).

-behaviour(gen_server).

-include("../include/gen_modbus.hrl").

%% API
-export([
    start_link/3,
    start_link/4,
    cast/2,
    call/2,
    call/3,
    stop/1,
    stop/3
    ]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    handle_continue/2,
    terminate/2,
    code_change/3
    ]).

-define(DEFAULT_SOCK_OPTS, [
    inet,
    binary,
    {active, true},
    {packet, raw},
    {reuseaddr, true},
    {nodelay, true}
    ]).

-record(state, {
    state,
    mod :: atom(),
    listen_sock :: [gen_tcp:socket()],
    sockets :: gen_tcp:socket(),
    coils :: lists:proplists(),
    holding :: lists:proplists(),
    buff = <<>>
    }).

start_link(Mod, Args, Options) ->
    gen_server:start_link(?MODULE, [Mod, Args], Options).

start_link(Name, Mod, Args, Options) ->
    gen_server:start_link(Name, ?MODULE, [Mod, Args], Options).

cast(Name, Message) ->
    gen_server:cast(Name, Message).

call(Name, Message) ->
    gen_server:call(Name, Message).

call(Name, Message, Timeout) ->
    gen_server:call(Name, Message, Timeout).

stop(Name) ->
    gen_server:stop(Name).

stop(Name, Reason, Timeout) ->
    gen_server:stop(Name, Reason, Timeout).

init([Mod, _Args]) ->
    case gen_tcp:listen(5000, ?DEFAULT_SOCK_OPTS) of
        {ok, LSock} ->
            {ok, #state{mod = Mod, listen_sock = LSock}, {continue, wait_connect}};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_continue(wait_connect, S) ->
    {ok, Sock} = gen_tcp:accept(S#state.listen_sock),
    {noreply, S#state{sockets = Sock}}.

handle_call(_Request, _From, S) ->
    {reply, ok, S}.

handle_cast(_Msg, S) ->
    {noreply, S}.

parser(Chunk, #state{buff = Buff} = S) ->
    parser_(<<Buff/binary, Chunk/binary>>, S).

parser_(<<Id:16, 0:16, MsgLen:16, Payload:MsgLen/binary, Tail/binary>>, S) ->
    parser__(Id, Payload, S#state{buff = Tail});

parser_(Buff, S) ->
    {noreply, S#state{buff = Buff}}.

parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16>>, S) ->
    Coils = [{RegNum, 0} | S#state.coils],
    gen_tcp:send(S#state.sockets, <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 0:16>>),
    parser_(S#state.buff, S#state{coils = Coils});

parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16>>, S) ->
    Coils = [{RegNum, 0} | S#state.coils],
    gen_tcp:send(S#state.sockets, <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_COIL:8, RegNum:16, 16#FF00:16>>),
    parser_(S#state.buff, S#state{coils = Coils});

parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>, S) ->
    Holding = [{RegNum, 0} | S#state.holding],
    gen_tcp:send(S#state.sockets, <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREG:8, RegNum:16, Value:16>>),
    parser_(S#state.buff, S#state{coils = Holding});

parser__(Id, <<DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, _RegQuantity:16, Len:8, Values:Len/binary>>, S) ->
    Val = bin_to_list16(Values, []),
    Quantity = length(Val),
    Holding = [{RegNum, 0} | S#state.holding],
    gen_tcp:send(S#state.sockets, <<Id:16, 0:16, 6:16, DevNum:8, ?FUN_CODE_WRITE_HREGS:8, RegNum:16, Quantity:16>>),
    parser_(S#state.buff, S#state{coils = Holding});

parser__(Id, Payload, S) ->
    io:format("Id is ~w payload is ~w~n", [Id, Payload]),
    parser_(S#state.buff, S).

handle_info({tcp, Socket, Data}, S) when Socket =:= S#state.sockets->
    parser(Data, S);

handle_info(_Info, S) ->
    {noreply, S}.

terminate(_Reason, _S) ->
    ok.

code_change(_OldVsn, S, _Extra) ->
    {ok, S}.

bin_to_list16(<<>>, Acc) ->
    lists:reverse(Acc);
bin_to_list16(<<H:16, T/binary>>, Acc) ->
    bin_to_list16(T, [H | Acc]).