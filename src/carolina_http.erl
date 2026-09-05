-module(carolina_http).
-behaviour(cowboy_handler).
-export([listen/0, init/2]).

listen() ->
    Port = carolina:port(),
    Dispatch = cowboy_router:compile([
        {'_', [{'_', ?MODULE, []}]}
    ]),
    Proto = #{env => #{dispatch => Dispatch}},
    %% Cowboy 2.12 / Ranch 1.8 want a proplist, not a ranch-2 map.
    V6 = [
        {port, Port},
        {ip, {0, 0, 0, 0, 0, 0, 0, 0}},
        {ipv6_v6only, false},
        {num_acceptors, 8},
        {max_connections, 256}
    ],
    case cowboy:start_clear(carolina_http, V6, Proto) of
        {ok, _} ->
            ok;
        {error, eafnosupport} ->
            V4 = [
                {port, Port},
                {ip, {0, 0, 0, 0}},
                {num_acceptors, 8},
                {max_connections, 256}
            ],
            {ok, _} = cowboy:start_clear(carolina_http, V4, Proto),
            ok;
        {error, {already_started, _}} ->
            ok
    end.

init(Req, State) ->
    Path = cowboy_req:path(Req),
    Qs = cowboy_req:parse_qs(Req),
    Year = proplists:get_value(<<"year">>, Qs, <<>>),
    {Code, Body} = carolina_handler:handle_get(Path, Year),
    Req2 = cowboy_req:reply(
        Code,
        #{<<"content-type">> => <<"application/json">>},
        Body,
        Req
    ),
    {ok, Req2, State}.
