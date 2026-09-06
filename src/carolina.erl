-module(carolina).
-behaviour(application).
-export([start/2, stop/1, main/0, port/0]).

-spec main() -> no_return().
main() ->
    {ok, _} = application:ensure_all_started(carolina),
    logger:notice("carolina-codes-erlang listening on [::]:~p", [port()]),
    wait_forever().

-spec start(application:start_type(), term()) -> {ok, pid()}.
start(_Type, _Args) ->
    {ok, Pid} = carolina_sup:start_link(),
    ok = carolina_http:listen(),
    spawn(fun carolina_register:once/0),
    {ok, Pid}.

-spec stop(term()) -> ok.
stop(_State) ->
    ok.

-spec port() -> inet:port_number().
port() ->
    case os:getenv("PORT") of
        false -> application:get_env(carolina, port, 4028);
        "" -> application:get_env(carolina, port, 4028);
        S -> list_to_integer(S)
    end.

-spec wait_forever() -> no_return().
wait_forever() ->
    receive
    after infinity ->
        wait_forever()
    end.
