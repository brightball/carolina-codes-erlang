-module(carolina_catalog_tests).
%% Drive shipped carolina_catalog:connect_map/1 — the map given to epgsql:connect/1.
-include_lib("eunit/include/eunit.hrl").

flycast_uses_inet6_test() ->
    Dsn = "postgres://carolina_codes_ro:secret@carolina-codes-db.flycast:5432/carolina_codes",
    Opts = carolina_catalog:connect_map(Dsn),
    ?assertEqual("carolina-codes-db.flycast", maps:get(host, Opts)),
    ?assertEqual(5432, maps:get(port, Opts)),
    ?assertEqual("carolina_codes", maps:get(database, Opts)),
    ?assertEqual("carolina_codes_ro", maps:get(username, Opts)),
    ?assertEqual(false, maps:get(ssl, Opts)),
    Tcp = maps:get(tcp_opts, Opts),
    ?assert(lists:member(inet6, Tcp)),
    ?assertNot(lists:member(inet, Tcp)).

internal_uses_inet6_test() ->
    Dsn = "postgres://u:p@carolina-codes-db.internal:5432/carolina_codes",
    Opts = carolina_catalog:connect_map(Dsn),
    ?assertEqual("carolina-codes-db.internal", maps:get(host, Opts)),
    Tcp = maps:get(tcp_opts, Opts),
    ?assertEqual([inet6], Tcp).

fly_io_uses_inet6_test() ->
    Dsn = <<"postgres://u:p@carolina-codes-db.fly.io:5432/carolina_codes">>,
    Opts = carolina_catalog:connect_map(Dsn),
    ?assert(lists:member(inet6, maps:get(tcp_opts, Opts))).

local_does_not_use_inet6_test() ->
    Dsn = "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev",
    Opts = carolina_catalog:connect_map(Dsn),
    ?assertEqual("127.0.0.1", maps:get(host, Opts)),
    ?assertEqual(false, maps:get(ssl, Opts)),
    ?assertEqual(error, maps:find(tcp_opts, Opts)).

localhost_does_not_use_inet6_test() ->
    Dsn = "postgres://postgres:postgres@localhost:5432/carolina_dev",
    Opts = carolina_catalog:connect_map(Dsn),
    ?assertEqual("localhost", maps:get(host, Opts)),
    ?assertEqual(error, maps:find(tcp_opts, Opts)).

sslmode_require_test() ->
    Dsn = "postgres://u:p@db.example.com:5432/db?sslmode=require",
    Opts = carolina_catalog:connect_map(Dsn),
    ?assertEqual(true, maps:get(ssl, Opts)),
    ?assertEqual(error, maps:find(tcp_opts, Opts)).

sslmode_disable_on_flycast_test() ->
    Dsn = "postgres://u:p@carolina-codes-db.flycast:5432/carolina_codes?sslmode=disable",
    Opts = carolina_catalog:connect_map(Dsn),
    ?assertEqual(false, maps:get(ssl, Opts)),
    ?assertEqual([inet6], maps:get(tcp_opts, Opts)).

connect_map_zero_uses_env_or_default_test() ->
    Opts = carolina_catalog:connect_map(),
    ?assert(is_map(Opts)),
    ?assert(is_list(maps:get(host, Opts))),
    ?assert(maps:is_key(ssl, Opts)),
    ?assert(maps:is_key(timeout, Opts)).
