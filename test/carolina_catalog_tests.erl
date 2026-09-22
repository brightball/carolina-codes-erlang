-module(carolina_catalog_tests).
%% Drive shipped carolina_catalog:connect_map/1 — the map given to epgsql:connect/1.
%% query_with/4 is the shipped query path with socket I/O injected.
-include_lib("eunit/include/eunit.hrl").
-include_lib("epgsql/include/epgsql.hrl").

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

%% Alive epgsql pid, dead socket: the next call must be a different connection.
dead_socket_opens_new_connection_test() ->
    Dead = hold(),
    Fresh = hold(),
    ok = carolina_catalog:cache_conn(Dead),
    put(step, first),
    ConnFun = fun() ->
        case get(step) of
            first -> Dead;
            second -> Fresh
        end
    end,
    Equery = fun(Conn, Sql, Params) ->
        ?assertEqual(<<"select 1">>, Sql),
        ?assertEqual([1], Params),
        case Conn of
            Dead ->
                put(step, second),
                {error, sock_closed};
            Fresh ->
                {ok, [#column{name = <<"n">>}], [{1}]}
        end
    end,
    try
        Rows = carolina_catalog:query_with(
            <<"select 1">>, [1], ConnFun, Equery
        ),
        ?assertEqual([#{<<"n">> => 1}], Rows),
        ?assertEqual(undefined, carolina_catalog:cached_conn()),
        ?assertEqual(false, is_process_alive(Dead)),
        ?assertEqual(true, is_process_alive(Fresh))
    after
        ok = carolina_catalog:cache_conn(undefined),
        exit(Dead, kill),
        exit(Fresh, kill)
    end.

sql_error_keeps_connection_test() ->
    Pid = hold(),
    ok = carolina_catalog:cache_conn(Pid),
    put(calls, 0),
    ConnFun = fun() ->
        put(calls, get(calls) + 1),
        Pid
    end,
    Reason = #error{
        severity = error,
        code = <<"42601">>,
        codename = syntax_error,
        message = <<"syntax error">>,
        extra = []
    },
    Equery = fun(_Conn, _Sql, _Params) -> {error, Reason} end,
    try
        ?assertError(
            {catalog_query, Reason},
            carolina_catalog:query_with(<<"select">>, [], ConnFun, Equery)
        ),
        ?assertEqual(1, get(calls)),
        ?assertEqual(true, is_process_alive(Pid)),
        ?assertEqual(Pid, carolina_catalog:cached_conn())
    after
        ok = carolina_catalog:cache_conn(undefined),
        exit(Pid, kill)
    end.

retries_once_then_errors_test() ->
    put(calls, 0),
    ConnFun = fun() ->
        put(calls, get(calls) + 1),
        hold()
    end,
    Equery = fun(Conn, _Sql, _Params) ->
        ?assertEqual(true, is_process_alive(Conn)),
        {error, closed}
    end,
    try
        ?assertError(
            {catalog_query, closed},
            carolina_catalog:query_with(<<"select 1">>, [], ConnFun, Equery)
        ),
        ?assertEqual(2, get(calls))
    after
        ok = carolina_catalog:cache_conn(undefined)
    end.

hold() ->
    spawn(fun() -> receive after 60000 -> ok end end).

%% Real query/2 against Postgres when the v1 relations exist.
live_query_reconnect_test_() ->
    case catalog_available() of
        true -> [{timeout, 30, fun live_query_reconnect/0}];
        false -> []
    end.

catalog_available() ->
    _ = application:ensure_all_started(epgsql),
    try epgsql:connect(carolina_catalog:connect_map()) of
        {ok, C} ->
            Result = epgsql:equery(C, "SELECT year FROM v1_years LIMIT 1", []),
            _ = epgsql:close(C),
            case Result of
                {ok, _, [_ | _]} -> true;
                _ -> false
            end;
        _ ->
            false
    catch
        _:_ -> false
    end.

live_query_reconnect() ->
    ok = carolina_catalog:cache_conn(undefined),
    Sql = <<"SELECT year, slug, name, status FROM v1_years ORDER BY year DESC">>,
    Rows1 = carolina_catalog:query(Sql, []),
    ?assert(length(Rows1) >= 1),
    Conn1 = carolina_catalog:cached_conn(),
    ?assert(is_pid(Conn1)),
    [#{<<"backend">> := Backend}] = carolina_catalog:query(
        <<"SELECT pg_backend_pid() AS backend">>, []
    ),
    ?assert(is_integer(Backend)),
    ok = quiet_terminate(Backend),
    Rows2 = carolina_catalog:query(Sql, []),
    ?assert(length(Rows2) >= 1),
    Conn2 = carolina_catalog:cached_conn(),
    ?assert(is_pid(Conn2)),
    ?assertNotEqual(Conn1, Conn2),
    ?assertNot(is_process_alive(Conn1)),
    ok = carolina_catalog:cache_conn(undefined),
    exit(Conn2, kill).

%% epgsql logs a crash when the server closes the socket. The retry
%% still succeeds; keep that report out of the test output.
quiet_terminate(BackendPid) ->
    {ok, #{level := Level}} = logger:get_handler_config(default),
    ok = logger:set_handler_config(default, level, none),
    try
        terminate_backend(BackendPid)
    after
        ok = logger:set_handler_config(default, level, Level)
    end.

terminate_backend(BackendPid) ->
    {ok, Admin} = epgsql:connect(carolina_catalog:connect_map()),
    try
        {ok, _, _} = epgsql:equery(
            Admin,
            "SELECT pg_terminate_backend($1)",
            [BackendPid]
        ),
        ok
    after
        _ = epgsql:close(Admin)
    end.
