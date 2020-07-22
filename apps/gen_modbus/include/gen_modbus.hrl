
-record(sock_info, {
    socket :: gen_tcp:socket(),
    connection :: close | open,
    ip_addr :: inet:socket_address() | inet:hostname(),
    port :: inet:port_number()
    }).

%%% ------------------------- COMMANDS RECORDS -------------------------
-record(connect, {
    ip_addr :: inet:socket_address() | inet:hostname(),
    port :: inet:port_number()
    }).

-record(disconnect, {
    reason :: term()
    }).

-record(change_sock_opts, {
    active :: true | false | once | -32768..32767,
    reuseaddr :: boolean(),
    nodelay :: boolean(),
    ifaddr :: inet | inet6
    }).

-record(read_register, {
    type :: holding | input,
    transaction_id = 1,
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: list(),
    error_code :: integer()
    }).

-record(read_status, {
    type :: coil | input,
    transaction_id = 1,
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: binary(),
    error_code :: integer()
    }).

-record(write_holding_register, {
    transaction_id = 1,
    device_number :: integer(),
    register_number :: integer(),
    register_value :: number(),
    error_code :: integer()
    }).

-record(write_holding_registers, {
    transaction_id = 1,
    device_number :: integer(),
    register_number :: integer(),
    registers_value :: list(),
    error_code :: integer()
    }).

-record(write_coil_status, {
    transaction_id = 1,
    device_number :: integer(),
    register_number :: integer(),
    register_value :: 0 | 1,
    error_code :: integer()
    }).

-record(write_coils_status, {
    transaction_id = 1,
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: binary(),
    error_code :: integer()
    }).
%%% ------------------------- COMMANDS RECORDS -------------------------

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
