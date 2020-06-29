-module(decryption_error_code).

-export([decrypt/1]).

decrypt(Err_code) ->
    
    case Err_code of
        
        16#01 -> 
            error_logger:error_msg("Error code: the accepted function code
                 cannot be processed.~n");

        16#02 ->
            error_logger:error_msg("Error code: the data address specified in
                 the request is not available.~n");

        16#03 ->
            error_logger:error_msg("Error code: the value contained in the request
                 data field is not a valid value.~n");

        16#04 ->
            error_logger:error_msg("Error code: an unrecoverable error occurred
                 while the slave was attempting to perform the requested action.~n");
        
        16#05 -> 
            error_logger:error_msg("Error code: the slave device has accepted the
                 request and is processing it, but this is time consuming.~n");

        16#06 ->
            error_logger:error_msg("Error code: the slave is busy
                 processing the command.~n");

        16#07 ->
            error_logger:error_msg("Error code: the slave cannot perform the
                 software function specified in the request.~n");

        16#08 -> 
            error_logger:error_msg("Error code: the slave encountered
                 a parity error while reading extended memory.~n");

        16#0A ->
            error_logger:error_msg("Error code: the gateway is configured
                 incorrectly or is overloaded with requests..~n");

        16#0B ->
            error_logger:error_msg("Error code: the device slave is offline
                 or there is no response from it.~n")

    end.
