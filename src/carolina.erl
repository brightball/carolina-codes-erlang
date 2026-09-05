-module(carolina).
-behaviour(application).
-export([start/2, stop/1, main/0, port/0]).

main() ->
    {ok, _} = application:ensure_all_started(carolina),
    io:format("carolina-codes-erlang listening on [::]:~p~n", [port()]),
    receive
    after infinity -> ok
    end.

start(_Type, _Args) ->
    {ok, Pid} = carolina_sup:start_link(),
    ok = carolina_http:listen(),
    spawn(fun carolina_register:once/0),
    {ok, Pid}.

stop(_State) ->
    ok.

port() ->
    case os:getenv("PORT") of
        false -> application:get_env(carolina, port, 4028);
        "" -> application:get_env(carolina, port, 4028);
        S -> list_to_integer(S)
    end.
