-type cmd() ::
    records:disconnect() |
    records:alarm() |
    wait_connect |
    {response, Socket :: gen_tcp:socket(), Response :: binary()} |
    {error_response, ErrCode :: integer(), Response :: binary(), Socket :: gen_tcp:socket()} |
    {stop, Reason :: term()}.

-type reg_info() ::
    records:write_coil() |
    records:write_coils() |
    records:read_coils() |

    records:write_hreg() |
    records:write_hregs() |
    records:read_hregs() |

    records:read_iregs() |

    records:read_inputs() |

    records:undefined_code().

%%% ------------------------- GEN SLAVE REGISTERS INFO ----------------------------
-record(write_coil, {
    reg_num :: integer(),
    val :: 0 | 1,
    response :: binary()
    }).

-record(write_coils, {
    reg_num :: integer(),
    quantity :: integer(),
    val :: 0 | 1,
    response :: binary()
    }).

-record(read_coils, {
    reg_num :: integer(),
    val :: undefined | binary(),
    response :: binary()
    }).

-record(write_hreg, {
    reg_num :: integer(),
    val :: 0 | 1,
    response :: binary()
    }).

-record(write_hregs, {
    reg_num :: integer(),
    val :: binary(),
    response :: binary()
    }).

-record(read_hregs, {
    reg_num :: integer(),
    val :: undefined | binary(),
    response :: binary()
    }).

-record(read_iregs, {
    reg_num :: integer(),
    val :: undefined | binary(),
    response :: binary()
    }).

-record(read_inputs, {
    reg_num :: integer(),
    val :: undefined | binary(),
    response :: binary()
    }).

-record(undefined_code, {
    response :: binary()
    }).

%%% ------------------------- GEN SLAVE REGISTERS INFO ----------------------------

%%% ------------------------- GEN SLAVE COMMANDS RECORDS --------------------------
-record(disconnect, {
    socket :: gen_tcp:socket(),
    reason :: term()
    }).

-record(response, {
    socket :: gen_tcp:socket(),
    response :: binary()
    }).

-record(error_response, {
    error_code :: integer(),
    response :: binary(),
    socket :: gen_tcp:socket()
    }).

-record(stop, {
    reason :: term()
    }).

-record(alarm, {
    type :: 1 | 2 | 3 | 4 | 5,
    status :: on | off
    }).

%%% ------------------------- GEN SLAVE COMMANDS RECORDS --------------------------
-define(FUN_CODE_READ_COILS,    16#01).
-define(FUN_CODE_READ_INPUTS,   16#02).
-define(FUN_CODE_READ_HREGS,    16#03).
-define(FUN_CODE_READ_IREGS,    16#04).
-define(FUN_CODE_WRITE_COIL,    16#05).
-define(FUN_CODE_WRITE_HREG,    16#06).
-define(FUN_CODE_WRITE_COILS,   16#0f).
-define(FUN_CODE_WRITE_HREGS,   16#10).

-define(ERR_CODE_READ_COILS,    16#81).
-define(ERR_CODE_READ_INPUTS,   16#82).
-define(ERR_CODE_READ_HREGS,    16#83).
-define(ERR_CODE_READ_IREGS,    16#84).
-define(ERR_CODE_WRITE_COIL,    16#85).
-define(ERR_CODE_WRITE_HREG,    16#86).
-define(ERR_CODE_WRITE_COILS,   16#8f).
-define(ERR_CODE_WRITE_HREGS,   16#90).