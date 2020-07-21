
%%% ------------------------- COMMANDS RECORDS -------------------------
-record(sock_info, {
    socket = undefined,
    connection = close,
    ip_addr = "localhost",
    port = 502
    }).

-record(connect, {
    ip_addr :: tuple(),
    port :: integer()
    }).

-record(disconnect, {
    reason :: term()
    }).

-record(change_sock_opts, {
    active :: boolean(),
    reuseaddr :: boolean(),
    nodelay :: boolean(),
    ifaddr :: inet | inet6
    }).

-record(read_register, {
    type :: holding | input,
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: list()
    }).

-record(read_status, {
    type :: coil | input,
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: binary()
    }).

-record(read_holding_registers, {
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: list(),
    error_code :: integer()
    }).

-record(read_input_registers, {
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: list(),
    error_code :: integer()
    }).

-record(read_coils_status, {
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: binary(),
    error_code :: integer()
    }).

-record(read_inputs_status, {
    device_number :: integer(),
    register_number :: integer(),
    quantity :: integer(),
    registers_value :: binary(),
    error_code :: integer()
    }).

-record(write_holding_register, {
    device_number :: integer(),
    register_number :: integer(),
    register_value :: number(),
    error_code :: integer()
    }).

-record(write_holding_registers, {
    device_number :: integer(),
    register_number :: integer(),
    registers_value :: list(),
    error_code :: integer()
    }).

-record(write_coil_status, {
    device_number :: integer(),
    register_number :: integer(),
    register_value :: 0 | 1,
    error_code :: integer()
    }).

-record(write_coils_status, {
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
