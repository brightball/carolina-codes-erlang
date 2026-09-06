-module(carolina_http_tests).
%% Drive shipped carolina_http cowboy_configuration/0 — the Nova listen bind.
-include_lib("eunit/include/eunit.hrl").

ipv6_dual_stack_test() ->
    Cfg = carolina_http:cowboy_configuration(),
    Ip = maps:get(ip, Cfg),
    ?assertEqual({0, 0, 0, 0, 0, 0, 0, 0}, Ip),
    ?assertEqual(8, tuple_size(Ip)),
    ?assertNotEqual({0, 0, 0, 0}, Ip),
    ?assertEqual(false, maps:get(ipv6_v6only, Cfg)).

configure_nova_test() ->
    ok = carolina_http:configure_nova(),
    {ok, carolina} = application:get_env(nova, bootstrap_application),
    {ok, Cfg} = application:get_env(nova, cowboy_configuration),
    ?assertEqual({0, 0, 0, 0, 0, 0, 0, 0}, maps:get(ip, Cfg)),
    ?assertEqual(false, maps:get(ipv6_v6only, Cfg)),
    ?assertEqual(carolina:port(), maps:get(port, Cfg)).

default_port_test() ->
    case os:getenv("PORT") of
        false -> ?assertEqual(4028, carolina:port());
        "" -> ?assertEqual(4028, carolina:port());
        _ -> ok
    end.
