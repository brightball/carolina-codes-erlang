-module(carolina_register).
-export([once/0]).

once() ->
    Url = os:getenv("CAROLINA_URL"),
    Token = os:getenv("POLYGLOT_REGISTER_TOKEN"),
    case {empty(Url), empty(Token)} of
        {false, false} -> post(Url, Token);
        _ -> ok
    end.

post(Url, Token) ->
    Base = case os:getenv("PUBLIC_BASE_URL") of
        false -> "http://127.0.0.1:" ++ integer_to_list(carolina:port());
        "" -> "http://127.0.0.1:" ++ integer_to_list(carolina:port());
        B -> B
    end,
    Body = carolina_identity:json_with_base(Base),
    Target = string:trim(Url, trailing, "/") ++ "/internal/api-endpoints/register",
    Headers = [
        {"authorization", "Bearer " ++ Token},
        {"content-type", "application/json"}
    ],
    case httpc:request(
        post,
        {Target, Headers, "application/json", Body},
        [{timeout, 5000}],
        [{body_format, binary}]
    ) of
        {ok, {{_, Code, Reason}, _, Resp}} ->
            io:format(standard_error, "registered with elixir: ~p ~s~n", [Code, Reason]),
            _ = Resp,
            ok;
        {error, Reason} ->
            io:format(standard_error, "register: failed ~p~n", [Reason]),
            ok
    end.

empty(false) -> true;
empty("") -> true;
empty(_) -> false.
