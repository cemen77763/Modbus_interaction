-record(function, {
    read_hreg = readH,
    read_coil = readC,
    read_inputs = readIs,
    read_hregs = readsH,
    read_iregs = readsI,
    read_ireg = readI,
    write_coil = writeC,
    write_hreg = writeH,
    write_hregs = writesH}).

-record(read_hreg, {
    device_num,
    register_num}).

-record(read_hregs, {
    device_num,
    register_num,
    quantity}).

-record(write_hreg, {
    device_num,
    register_num,
    value}).

-record(write_hregs, {
    device_num,
    register_num,
    values}).

-record(read_ireg, {
    device_num,
    register_num}).

-record(read_iregs, {
    device_num,
    register_num,
    quantity}).

-record(write_coil, {
    device_num,
    register_num,
    value}).

-record(read_coil, {
    device_num,
    register_num}).

-record(read_inputs, {
    device_num,
    register_num}).

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
