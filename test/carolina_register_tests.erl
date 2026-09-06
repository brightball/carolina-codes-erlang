-module(carolina_register_tests).
%% Drive shipped carolina_register profile_options/1 and uses_inet6/1.
-include_lib("eunit/include/eunit.hrl").

internal_uses_inet6_test() ->
    Url = "http://carolina-codes.internal:8080/internal/api-endpoints/register",
    ?assert(carolina_register:uses_inet6(Url)),
    Opts = carolina_register:profile_options(Url),
    ?assertEqual(inet6, proplists:get_value(ipfamily, Opts)),
    ?assert(lists:member({ipfamily, inet6}, Opts)).

internal_host_port_uses_inet6_test() ->
    Url = <<"http://carolina-codes-erlang.internal:8080">>,
    ?assert(carolina_register:uses_inet6(Url)).

local_does_not_use_inet6_test() ->
    Url = "http://127.0.0.1:4000/internal/api-endpoints/register",
    ?assertNot(carolina_register:uses_inet6(Url)),
    Opts = carolina_register:profile_options(Url),
    ?assertEqual(inet, proplists:get_value(ipfamily, Opts)),
    ?assertNot(lists:member({ipfamily, inet6}, Opts)).

localhost_does_not_use_inet6_test() ->
    Url = "http://localhost:4000/internal/api-endpoints/register",
    ?assertNot(carolina_register:uses_inet6(Url)).
