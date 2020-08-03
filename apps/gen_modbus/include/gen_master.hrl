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
    registers_value :: integer() | undefined,
    error_code :: integer() | undefined
    }).
%%% ------------------------- GEN MASTER COMMANDS RECORDS -------------------------