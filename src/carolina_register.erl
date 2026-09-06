-module(carolina_register).
-export([once/0, uses_inet6/1, profile_options/1]).

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
    Profile = carolina_httpc,
    ok = ensure_profile(Profile),
    ok = httpc:set_options(profile_options(Target), Profile),
    HTTPOpts = [{timeout, 8000}, {connect_timeout, 8000}],
    case httpc:request(
        post,
        {Target, Headers, "application/json", Body},
        HTTPOpts,
        [{body_format, binary}],
        Profile
    ) of
        {ok, {{_, Code, Reason}, _, Resp}} ->
            io:format(standard_error, "registered with elixir: ~p ~s~n", [Code, Reason]),
            _ = Resp,
            ok;
        {error, Reason} ->
            io:format(standard_error, "register: failed ~p~n", [Reason]),
            ok
    end.

%% inet6 only for Fly 6PN (*.internal:port). Never set the default httpc profile.
uses_inet6(Url) when is_binary(Url) ->
    uses_inet6(binary_to_list(Url));
uses_inet6(Url) when is_list(Url) ->
    string:find(Url, ".internal:") =/= nomatch.

profile_options(Url) ->
    case uses_inet6(Url) of
        true -> [{ipfamily, inet6}];
        false -> [{ipfamily, inet}]
    end.

ensure_profile(Profile) ->
    case inets:start(httpc, [{profile, Profile}]) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        {error, {already_started, _, _}} -> ok
    end.

empty(false) -> true;
empty("") -> true;
empty(_) -> false.
