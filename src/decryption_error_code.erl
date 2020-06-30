-module(decryption_error_code).

-export([decrypt/1]).

decrypt(16#01) ->
    error_logger:error_msg("Error code: the accepted function code cannot be proc
        essed.~n");

decrypt(16#02) ->
    error_logger:error_msg("Error code: the data address specified in the request
         is not available.~n");

decrypt(16#03) ->
    error_logger:error_msg("Error code: the value contained in the request data f
        ield is not a valid value.~n");

decrypt(16#04) ->
    error_logger:error_msg("Error code: an unrecoverable error occurred while the
         slave was attempting to perform the requested action.~n");

decrypt(16#05) ->
    error_logger:error_msg("Error code: the slave device has accepted the request
         and is processing it, but this is time consuming.~n");

decrypt(16#06) ->
    error_logger:error_msg("Error code: the slave is busy processing the command.
        ~n");

decrypt(16#07) ->
    error_logger:error_msg("Error code: the slave cannot perform the software fun
        ction specified in the request.~n");

decrypt(16#08) ->
    error_logger:error_msg("Error code: the gateway is configured incorrectly or 
        is overloaded with requests..~n");

decrypt(16#0A) ->
    error_logger:error_msg("Error code: the gateway is configured incorrectly or 
        is overloaded with requests..~n");

decrypt(16#0B) ->
    error_logger:error_msg("Error code: the device slave is offline or there is n
        o response from it.~n").

