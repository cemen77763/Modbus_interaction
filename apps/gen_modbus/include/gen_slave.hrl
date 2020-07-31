-type cmd() ::
    records:disconnect() |
    records:alarm() |
    wait_connect |
    {stop, Reason :: term()}.

%%% ------------------------- GEN SLAVE COMMANDS RECORDS --------------------------

-record(disconnect, {
    socket :: gen_tcp:socket(),
    reason :: term()
    }).

-record(alarm, {
    type :: 1 | 2 | 3 | 4 | 5,
    status :: on | off
    }).

%%% ------------------------- GEN SLAVE COMMANDS RECORDS --------------------------