-module(carolina_catalog).
%% query/2 is live SQL. connect_map/1 is the map passed to epgsql:connect/1.
%% query_with/4 is that same query with the socket calls injected so a
%% dead cached connection can be forced without Postgres.
-export([
    query/2,
    query_with/4,
    cache_conn/1,
    cached_conn/0,
    connect_map/0,
    connect_map/1
]).

-include_lib("epgsql/include/epgsql.hrl").

-define(CONN_KEY, {?MODULE, conn}).
%% One retry after a dead socket. Matches the connect timeout.
-define(QUERY_TIMEOUT, 5000).

-spec query(iodata(), [term()]) -> [map()].
query(Sql, Args) ->
    query_with(Sql, Args, fun conn/0, fun bounded_equery/3).

-spec query_with(
    iodata(),
    [term()],
    fun(() -> pid()),
    fun((pid(), binary(), [term()]) -> term())
) -> [map()].
query_with(Sql, Args, ConnFun, EqueryFun) ->
    attempt(Sql, Args, ConnFun, EqueryFun, 1).

attempt(Sql, Args, ConnFun, EqueryFun, Left) ->
    Conn = ConnFun(),
    SqlB = iolist_to_binary(Sql),
    Params = [coerce_arg(A) || A <- Args],
    case safe_equery(EqueryFun, Conn, SqlB, Params) of
        {ok, Columns, Rows} ->
            rows_to_maps(Columns, Rows);
        {ok, _Count} ->
            [];
        {ok, _Count, Columns, Rows} ->
            rows_to_maps(Columns, Rows);
        {error, Reason} ->
            finish_error(Sql, Args, ConnFun, EqueryFun, Left, Conn, Reason)
    end.

finish_error(Sql, Args, ConnFun, EqueryFun, Left, Conn, Reason) ->
    case connection_failure(Reason) of
        true ->
            drop_conn(Conn),
            case Left > 0 of
                true ->
                    attempt(Sql, Args, ConnFun, EqueryFun, Left - 1);
                false ->
                    error({catalog_query, Reason})
            end;
        false ->
            error({catalog_query, Reason})
    end.

%% SQL errors stay on the open connection. Socket loss, a fatal Postgres
%% error, or a dead process do not.
connection_failure(#error{severity = fatal}) -> true;
connection_failure(#error{severity = panic}) -> true;
connection_failure(#error{}) -> false;
connection_failure(_) -> true.

safe_equery(Fun, Conn, Sql, Params) ->
    try Fun(Conn, Sql, Params) of
        Result -> Result
    catch
        exit:Reason -> {error, {exit, Reason}}
    end.

rows_to_maps(Columns, Rows) ->
    Names = [col_name(C) || C <- Columns],
    [row_map(Names, tuple_to_list(R)) || R <- Rows].

bounded_equery(Conn, Sql, Params) ->
    Parent = self(),
    Ref = make_ref(),
    Worker = spawn(fun() ->
        Result = try epgsql:equery(Conn, Sql, Params) of
            Value -> Value
        catch
            exit:Reason -> {error, {exit, Reason}}
        end,
        Parent ! {Ref, Result}
    end),
    Mon = erlang:monitor(process, Conn),
    receive
        {Ref, Result} ->
            _ = erlang:demonitor(Mon, [flush]),
            Result;
        {'DOWN', Mon, process, Conn, Reason} ->
            exit(Worker, kill),
            receive {Ref, _} -> ok after 0 -> ok end,
            {error, {exit, Reason}}
    after ?QUERY_TIMEOUT ->
        _ = erlang:demonitor(Mon, [flush]),
        exit(Worker, kill),
        {error, timeout}
    end.

%% v1 year columns are int8; epgsql will not encode <<"2026">> as int8.
coerce_arg(I) when is_integer(I) -> I;
coerce_arg(B) when is_binary(B) ->
    case string:to_integer(string:trim(B)) of
        {N, Rest} when is_integer(N), Rest =:= <<>> -> N;
        {N, Rest} when is_integer(N), Rest =:= [] -> N;
        _ -> B
    end;
coerce_arg(L) when is_list(L) -> coerce_arg(list_to_binary(L)).

col_name(#column{name = Name}) ->
    Name.

row_map(Names, Vals) ->
    maps:from_list(lists:zip(Names, [cell(V) || V <- Vals])).

cell(null) -> null;
cell(V) when is_binary(V); is_integer(V); is_float(V); is_boolean(V) -> V;
cell(V) when is_list(V) -> V;
cell({array, L}) -> L;
cell(V) -> iolist_to_binary(io_lib:format("~p", [V])).

conn() ->
    case cached_conn() of
        C when is_pid(C) ->
            case is_process_alive(C) of
                true -> C;
                false -> connect()
            end;
        _ ->
            connect()
    end.

connect() ->
    {ok, C} = epgsql:connect(connect_map()),
    %% epgsql links the socket owner to the caller. A dead socket would
    %% then kill the request before the retry can open a new connection.
    true = unlink(C),
    ok = cache_conn(C),
    C.

-spec cached_conn() -> pid() | undefined.
cached_conn() ->
    persistent_term:get(?CONN_KEY, undefined).

-spec cache_conn(pid() | undefined) -> ok.
cache_conn(undefined) ->
    _ = persistent_term:erase(?CONN_KEY),
    ok;
cache_conn(Pid) when is_pid(Pid) ->
    persistent_term:put(?CONN_KEY, Pid),
    ok.

%% Forget a broken connection so the retry (and the next request) open
%% a new socket. epgsql:close/1 can block forever on a dead fd.
drop_conn(Conn) ->
    case cached_conn() of
        Conn -> ok = cache_conn(undefined);
        _ -> ok
    end,
    abandon(Conn).

abandon(Conn) when is_pid(Conn) ->
    true = unlink(Conn),
    exit(Conn, kill),
    ok;
abandon(_) ->
    ok.

-spec connect_map() -> map().
connect_map() ->
    Dsn = case os:getenv("DATABASE_URL") of
        false -> "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev";
        "" -> "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev";
        S -> S
    end,
    connect_map(Dsn).

%% Options actually given to epgsql:connect/1. Fly .flycast/.internal
%% hostnames are AAAA-only; without tcp_opts inet6, gen_tcp returns nxdomain.
-spec connect_map(iodata()) -> map().
connect_map(Dsn0) ->
    Parsed = parse_dsn(Dsn0),
    Host = maps:get(host, Parsed),
    Opts = Parsed#{timeout => 5000},
    case needs_inet6(Host) of
        true -> Opts#{tcp_opts => [inet6]};
        false -> Opts
    end.

needs_inet6(Host) when is_list(Host) ->
    lists:suffix(".flycast", Host)
        orelse lists:suffix(".internal", Host)
        orelse lists:suffix(".fly.io", Host).

parse_dsn(Dsn0) ->
    Dsn = iolist_to_binary(Dsn0),
    URI = case uri_string:parse(Dsn) of
        #{scheme := _} = U -> U;
        _ -> uri_string:parse(<<"postgres://postgres:postgres@127.0.0.1:5432/carolina_dev">>)
    end,
    Host = to_list(maps:get(host, URI, <<"127.0.0.1">>)),
    Port = case maps:get(port, URI, 5432) of
        undefined -> 5432;
        P -> P
    end,
    Path = to_list(maps:get(path, URI, <<"/carolina_dev">>)),
    Database = string:trim(Path, leading, "/"),
    {User, Pass} = split_userinfo(maps:get(userinfo, URI, <<"postgres:postgres">>)),
    #{
        host => Host,
        port => Port,
        username => User,
        password => Pass,
        database => Database,
        ssl => ssl_from_uri(URI)
    }.

ssl_from_uri(URI) ->
    ssl_from_query(maps:get(query, URI, undefined)).

ssl_from_query(undefined) -> false;
ssl_from_query(<<>>) -> false;
ssl_from_query("") -> false;
ssl_from_query(Query) ->
    Pairs = uri_string:dissect_query(Query),
    Mode = query_val(Pairs, "sslmode"),
    ssl_mode(to_list(Mode)).

query_val(Pairs, Key) ->
    case proplists:get_value(Key, Pairs, undefined) of
        undefined ->
            proplists:get_value(list_to_binary(Key), Pairs, "disable");
        V ->
            V
    end.

ssl_mode("require") -> true;
ssl_mode("verify-ca") -> true;
ssl_mode("verify-full") -> true;
ssl_mode(_) -> false.

split_userinfo(undefined) -> {"postgres", "postgres"};
split_userinfo(Info) ->
    S = to_list(Info),
    case string:split(S, ":") of
        [U, P] -> {U, uri_decode(P)};
        [U] -> {U, ""};
        _ -> {"postgres", "postgres"}
    end.

uri_decode(S) ->
    case uri_string:percent_decode(S) of
        {error, _, _} -> S;
        D -> to_list(D)
    end.

to_list(B) when is_binary(B) -> binary_to_list(B);
to_list(L) when is_list(L) -> L;
to_list(A) when is_atom(A) -> atom_to_list(A).
