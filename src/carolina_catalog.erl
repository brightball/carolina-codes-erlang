-module(carolina_catalog).
-export([query/2]).

-include_lib("epgsql/include/epgsql.hrl").

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

col_name(#column{name = Name}) when is_binary(Name) -> Name;
col_name(#column{name = Name}) when is_atom(Name) -> atom_to_binary(Name, utf8);
col_name(#column{name = Name}) when is_list(Name) -> list_to_binary(Name).

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

connect_map() ->
    Dsn = case os:getenv("DATABASE_URL") of
        false -> "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev";
        "" -> "postgres://postgres:postgres@127.0.0.1:5432/carolina_dev";
        S -> S
    end,
    Parsed = parse_dsn(Dsn),
    Parsed#{timeout => 5000, ssl => false}.

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
        database => Database
    }.

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
