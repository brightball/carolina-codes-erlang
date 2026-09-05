-module(carolina_identity).
-export([json/0, json_with_base/1, language/0, framework/0, language_version/0]).

language() -> <<"Erlang">>.
framework() -> <<"Cowboy">>.

language_version() ->
    iolist_to_binary(["OTP ", erlang:system_info(otp_release)]).

endpoints() ->
    [
        #{method => <<"GET">>, path => <<"/">>, query => []},
        #{method => <<"GET">>, path => <<"/health">>, query => []},
        #{method => <<"GET">>, path => <<"/v1/years">>, query => []},
        #{method => <<"GET">>, path => <<"/v1/speakers">>, query => [<<"year">>]},
        #{method => <<"GET">>, path => <<"/v1/speakers/:slug">>, query => []},
        #{method => <<"GET">>, path => <<"/v1/speakers/:year/:slug">>, query => []},
        #{method => <<"GET">>, path => <<"/v1/sponsors">>, query => [<<"year">>]},
        #{method => <<"GET">>, path => <<"/v1/sponsors/:slug">>, query => []},
        #{method => <<"GET">>, path => <<"/v1/sponsors/:year/:slug">>, query => []}
    ].

json() ->
    carolina_json:encode(#{
        language => language(),
        language_version => language_version(),
        api_version => <<"0.2.0">>,
        framework => framework(),
        created_year => 2026,
        schema_version => 1,
        endpoints => endpoints()
    }).

json_with_base(Base) ->
    carolina_json:encode(#{
        language => language(),
        language_version => language_version(),
        api_version => <<"0.2.0">>,
        framework => framework(),
        created_year => 2026,
        schema_version => 1,
        endpoints => endpoints(),
        base_url => iolist_to_binary(Base)
    }).
