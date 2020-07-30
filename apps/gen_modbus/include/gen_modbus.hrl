
-type cmd() ::
    record:connect() |
    record:disconnect() |
    record:change_sock_opts() |
    record:read_register() |
    record:read_status() |
    record:write_holding_register() |
    record:write_holding_registers() |
    record:write_coil_status() |
    record:write_coils_status() |
    record:wait_connect() |
    record:alarm().

-record(sock_info, {
    socket :: gen_tcp:socket() | undefined,
    ip_addr :: inet:socket_address() | inet:hostname() | undefined,
    port :: inet:port_number() | undefined
    }).

%%% ------------------------- GEN MASTER COMMANDS RECORDS -------------------------
-record(connect, {
    ip_addr :: inet:socket_address() | inet:hostname(),
    port :: inet:port_number()
    }).

-record(disconnect, {
    reason :: term()
    }).

-record(change_sock_opts, {
    reuseaddr :: boolean() | undefined,
    nodelay :: boolean() | undefined,
    ifaddr :: inet | inet6 | undefined
    }).

-record(read_register, {
    type :: holding | input,
    transaction_id :: integer(),
    device_number :: integer() | undefined,
    register_number :: integer() | undefined,
    quantity :: integer() | undefined,
    registers_value :: list() | undefined,
    error_code :: integer() | undefined
    }).

-record(read_status, {
    type :: coil | input,
    transaction_id :: integer(),
    device_number :: integer() | undefined,
    register_number :: integer() | undefined,
    quantity :: integer() | undefined,
    registers_value :: binary() | undefined,
    error_code :: integer() | undefined
    }).

-record(write_holding_register, {
    transaction_id :: integer(),
    device_number :: integer() | undefined,
    register_number :: integer() | undefined,
    register_value :: number() | undefined,
    error_code :: integer() | undefined
    }).

-record(write_holding_registers, {
    transaction_id :: integer(),
    device_number :: integer() | undefined,
    register_number :: integer() | undefined,
    registers_value :: list() | undefined,
    error_code :: integer() | undefined
    }).

-record(write_coil_status, {
    transaction_id :: integer(),
    device_number :: integer() | undefined,
    register_number :: integer() | undefined,
    register_value :: 0 | 1 | undefined,
    error_code :: integer() | undefined
    }).

-record(write_coils_status, {
    transaction_id :: integer(),
    device_number :: integer() | undefined,
    register_number :: integer() | undefined,
    quantity :: integer() | undefined,
    registers_value :: binary() | undefined,
    error_code :: integer() | undefined
    }).
%%% ------------------------- GEN MASTER COMMANDS RECORDS -------------------------

%%% ------------------------- GEN SLAVE COMMANDS RECORDS --------------------------

-record(wait_connect, {
    ip_addr :: inet:socket_address() | inet:hostname() | undefined,
    port :: inet:port_number() | undefined
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
