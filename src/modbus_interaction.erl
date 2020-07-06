%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc This module send messages to gen server for interact with Modbus TCP device          %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(modbus_interaction).

-include("modbus_functional_codes.hrl").

-export([
    read_Hreg/2,
    read_Hregs/3, 
    read_Ireg/2,
    read_Iregs/3,
    read_Creg/2,
    read_Isreg/2,
    write_Creg/3,
    write_Hreg/3,
    write_Hregs/3]).
 
-define(SERVER, modbus_gen).


%% Отправка сообщения для прочтения 1 Holding reg
read_Hreg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, #read_hreg{device_num = Device_num, register_num = Reg_num}).


%% Отправка сообщения для прочтения N Holding regs
read_Hregs(Device_num, Reg_num, Quantity) ->
    gen_server:call(?SERVER, #read_hregs{device_num = Device_num, register_num = Reg_num, quantity = Quantity}).


%% Отправка сообщения для записи 1 Holding reg
write_Hreg(Device_num, Reg_num, Value) ->
    gen_server:call(?SERVER, #write_hreg{device_num = Device_num, register_num = Reg_num, value = Value}).


%% Отправка сообщения для записи N Holding regs
write_Hregs(Device_num, Reg_num, Values) when is_list(Values) ->
    gen_server:call(?SERVER, #write_hregs{device_num = Device_num, register_num = Reg_num, values = Values}).


%% Отправка сообщения для прочтения 1 Input regs
read_Ireg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, #read_ireg{device_num = Device_num, register_num = Reg_num}).


%% Отправка сообщения для прочтения N Input regs
read_Iregs(Device_num, Reg_num, Quantity) ->
    gen_server:call(?SERVER, #read_iregs{device_num = Device_num, register_num = Reg_num, quantity = Quantity}).


%% Отправка сообщения для записи Coil status
write_Creg(Device_num, Reg_num, Value) ->
    gen_server:call(?SERVER, #write_coil{device_num = Device_num, register_num = Reg_num, value = Value}).


%% Отправка сообщения для прочтения Coil status
read_Creg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, #read_coil{device_num = Device_num, register_num = Reg_num}).


%% Отправка сообщения для прочтения Input status
read_Isreg(Device_num, Reg_num) ->
    gen_server:call(?SERVER, #read_inputs{device_num = Device_num, register_num = Reg_num}).