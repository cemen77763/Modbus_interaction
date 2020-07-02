%%% ----------------------------------------------------------------------------------------- %%%
%%% @doc Conversion list to binary 16bits                                                     %%%
%%% @end                                                                                      %%%
%%% ----------------------------------------------------------------------------------------- %%%

-module(bin_conversion).

-export([list_to_bin16/2]).


list_to_bin16([], Acc) ->
    Acc;

list_to_bin16([H | T], Acc) ->
    list_to_bin16(T, <<Acc/binary, H:16>>).
