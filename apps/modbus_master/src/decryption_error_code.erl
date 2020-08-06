%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc Decrypt error code recived from Modbus TCP slave devices                                   %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(decryption_error_code).

-export([decrypt/1]).

decrypt(16#01) ->
    error_logger:error_msg("Error code: the accepted function code cannot be processed."),
    16#01;

decrypt(16#02) ->
    error_logger:error_msg("Error code: the data address specified in the requestis not available."),
    16#02;

decrypt(16#03) ->
    error_logger:error_msg("Error code: the value contained in the request data field is not a valid value."),
    16#03;

decrypt(16#04) ->
    error_logger:error_msg("Error code: an unrecoverable error occurred while theslave was attempting to perform the requested action."),
    16#04;

decrypt(16#05) ->
    error_logger:error_msg("Error code: the slave device has accepted the requestand is processing it, but this is time consuming."),
    16#05;

decrypt(16#06) ->
    error_logger:error_msg("Error code: the slave is busy processing the command."),
    16#06;

decrypt(16#07) ->
    error_logger:error_msg("Error code: the slave cannot perform the software function specified in the request."),
    16#07;

decrypt(16#08) ->
    error_logger:error_msg("Error code: the gateway is configured incorrectly or is overloaded with requests."),
    16#08;

decrypt(16#0A) ->
    error_logger:error_msg("Error code: the gateway is configured incorrectly or is overloaded with requests."),
    16#0A;

decrypt(16#0B) ->
    error_logger:error_msg("Error code: the device slave is offline or there is no response from it."),
    16#0B;

decrypt(Err) ->
    error_logger:error_msg("Error code: ~w", Err),
    Err.

