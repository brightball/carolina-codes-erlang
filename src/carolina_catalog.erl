-module(carolina_catalog).
%% query/2 is live SQL. connect_map/1 is the map passed to epgsql:connect/1.
-export([query/2, connect_map/0, connect_map/1]).

-include_lib("epgsql/include/epgsql.hrl").

-spec query(iodata(), [term()]) -> [map()].
query(Sql, Args) ->
    Conn = conn(),
    SqlB = iolist_to_binary(Sql),
    Params = [coerce_arg(A) || A <- Args],
    case epgsql:equery(Conn, SqlB, Params) of
        {ok, Columns, Rows} ->
            Names = [col_name(C) || C <- Columns],
            [row_map(Names, tuple_to_list(R)) || R <- Rows];
        {ok, _Count} ->
            [];
        {error, Reason} ->
            error({catalog_query, Reason})
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
    case persistent_term:get({?MODULE, conn}, undefined) of
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
    persistent_term:put({?MODULE, conn}, C),
    C.

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
