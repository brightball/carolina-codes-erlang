-module(carolina_handler_tests).
%% Drive shipped carolina_handler:handle_get/3 and Nova controllers —
%% not a reimplementation.
-include_lib("eunit/include/eunit.hrl").

has(Body, Sub) ->
    binary:match(iolist_to_binary(Body), iolist_to_binary(Sub)) =/= nomatch.

json_body({json, Map}) ->
    carolina_json:encode(Map);
json_body({json, _Status, _Headers, Map}) ->
    carolina_json:encode(Map).

speaker() ->
    #{
        <<"slug">> => <<"diana-pham">>,
        <<"first_name">> => <<"Diana">>,
        <<"last_name">> => <<"Pham">>,
        <<"name">> => <<"Diana Pham">>
    }.

talk() ->
    #{
        <<"slug">> => <<"talk">>,
        <<"title">> => <<"Talk">>,
        <<"youtube_id">> => <<"abc123">>,
        <<"speaker_slug">> => <<"diana-pham">>,
        <<"year">> => <<"2026">>,
        <<"languages">> => <<"{php}">>,
        <<"topics">> => <<"{development}">>
    }.

year_sponsor() ->
    #{
        <<"slug">> => <<"flywheel">>,
        <<"name">> => <<"Flywheel">>,
        <<"tier">> => <<"platinum">>,
        <<"year">> => <<"2026">>
    }.

sponsor_row() ->
    #{
        <<"slug">> => <<"flywheel">>,
        <<"name">> => <<"Flywheel">>
    }.

year_row() ->
    #{
        <<"year">> => <<"2026">>,
        <<"slug">> => <<"2026">>,
        <<"name">> => <<"Carolina Code Conference 2026">>,
        <<"status">> => <<"past">>
    }.

fake(Sql0, Args) ->
    Sql = iolist_to_binary(Sql0),
    put(sqls, [Sql | case get(sqls) of undefined -> []; L -> L end]),
    Arg0 = case Args of [A0 | _] -> A0; [] -> <<>> end,
    Arg1 = case Args of [_A0, A1 | _] -> A1; _ -> <<>> end,
    pick(Sql, to_bin(Arg0), to_bin(Arg1)).

pick(Sql, Arg0, Arg1) ->
    case has(Sql, <<"v1_speakers WHERE slug =">>) of
        true ->
            case Arg0 of
                <<"diana-pham">> -> [speaker()];
                _ -> []
            end;
        false -> pick_speakers(Sql, Arg0, Arg1)
    end.

pick_speakers(Sql, Arg0, Arg1) ->
    case has(Sql, <<"v1_speakers">>) of
        true -> [speaker()];
        false -> pick_talks(Sql, Arg0, Arg1)
    end.

pick_talks(Sql, Arg0, Arg1) ->
    case has(Sql, <<"v1_talks">>) of
        true -> [talk()];
        false -> pick_year_sponsors(Sql, Arg0, Arg1)
    end.

pick_year_sponsors(Sql, Arg0, Arg1) ->
    case has(Sql, <<"v1_year_sponsors">>) of
        true ->
            case Arg1 of
                <<"missing-sponsor">> -> [];
                _ -> [year_sponsor()]
            end;
        false -> pick_sponsors_slug(Sql, Arg0, Arg1)
    end.

pick_sponsors_slug(Sql, Arg0, Arg1) ->
    %% Arg0 is the first SQL arg; for WHERE slug = $1 it is the slug.
    case has(Sql, <<"v1_sponsors WHERE slug">>) of
        true ->
            case Arg0 of
                <<"flywheel">> -> [sponsor_row()];
                _ -> []
            end;
        false -> pick_sponsors(Sql, Arg1)
    end.

pick_sponsors(Sql, _Arg1) ->
    case has(Sql, <<"v1_sponsors">>) of
        true -> [sponsor_row()];
        false -> pick_years(Sql)
    end.

pick_years(Sql) ->
    case has(Sql, <<"v1_years">>) of
        true -> [year_row()];
        false ->
            case has(Sql, <<"v1_sponsorships">>) of
                true -> [];
                false -> []
            end
    end.

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(undefined) -> <<>>.

boom(_, _) -> error(touched_postgres).

req(Path) ->
    #{path => Path, parsed_qs => [], bindings => #{}}.

req(Path, Year) ->
    #{path => Path, parsed_qs => [{<<"year">>, Year}], bindings => #{}}.

req_bind(Path, Bindings) ->
    #{path => Path, parsed_qs => [], bindings => Bindings}.

health_test() ->
    put(sqls, []),
    {json, Map} = carolina_handler:handle_get(<<"/health">>, <<>>, fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"\"status\"">>)),
    ?assert(has(Body, <<"\"ok\"">>)),
    ?assertEqual([], get(sqls)).

health_no_sql_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/health">>, <<>>, fun boom/2),
    ?assertEqual(<<"ok">>, maps:get(status, Map)).

health_slash_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/health/">>, <<>>, fun fake/2),
    ?assert(has(json_body({json, Map}), <<"ok">>)).

health_controller_test() ->
    {json, Map} = carolina_main_controller:health(req(<<"/health">>), fun boom/2),
    ?assertEqual(<<"ok">>, maps:get(status, Map)).

identity_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/">>, <<>>, fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"Erlang">>)),
    ?assert(has(Body, <<"Nova">>)),
    ?assertNot(has(Body, <<"Cowboy">>)),
    ?assertNot(has(Body, <<"Gleam">>)),
    ?assertNot(has(Body, <<"mist">>)),
    ?assertEqual(<<"Erlang">>, maps:get(language, Map)),
    ?assertEqual(<<"Nova">>, maps:get(framework, Map)).

identity_controller_test() ->
    {json, Map} = carolina_main_controller:index(req(<<"/">>), fun boom/2),
    ?assertEqual(<<"Erlang">>, maps:get(language, Map)),
    ?assertEqual(<<"Nova">>, maps:get(framework, Map)).

years_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/v1/years">>, <<>>, fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"\"data\"">>)),
    Data = maps:get(data, Map),
    ?assert(is_list(Data)),
    ?assert(Data =/= []).

years_controller_test() ->
    {json, Map} = carolina_v1_controller:years(req(<<"/v1/years">>), fun fake/2),
    ?assert(is_list(maps:get(data, Map))).

unscoped_speakers_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/v1/speakers">>, <<>>, fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"\"data\"">>)),
    ?assert(has(Body, <<"diana-pham">>)).

year_speakers_test() ->
    put(sqls, []),
    {json, Map} = carolina_handler:handle_get(<<"/v1/speakers">>, <<"2026">>, fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"\"data\"">>)),
    ?assert(has(Body, <<"languages">>)),
    ?assert(has(Body, <<"topics">>)),
    ?assert(has(Body, <<"php">>)),
    ?assert(has(Body, <<"development">>)),
    Sqls = get(sqls),
    ?assert(lists:any(fun(S) -> has(S, <<"v1_talks">>) end, Sqls)),
    ?assertNot(lists:any(fun(S) -> has(S, <<"v1_year_speakers">>) end, Sqls)).

year_speakers_controller_test() ->
    {json, Map} = carolina_v1_controller:speakers(req(<<"/v1/speakers">>, <<"2026">>), fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"languages">>)),
    ?assert(has(Body, <<"topics">>)).

speaker_detail_test() ->
    {json, Map} = carolina_handler:handle_get(
        <<"/v1/speakers/diana-pham">>, <<>>, fun fake/2
    ),
    Data = maps:get(data, Map),
    Talks = maps:get(<<"talks">>, Data),
    ?assert(is_list(Talks)),
    ?assert(Talks =/= []).

speaker_detail_controller_test() ->
    Req = req_bind(<<"/v1/speakers/diana-pham">>, #{<<"slug">> => <<"diana-pham">>}),
    {json, Map} = carolina_v1_controller:speaker(Req, fun fake/2),
    ?assertEqual(<<"diana-pham">>, maps:get(<<"slug">>, maps:get(data, Map))).

speaker_year_detail_test() ->
    {json, Map} = carolina_handler:handle_get(
        <<"/v1/speakers/2026/diana-pham">>, <<>>, fun fake/2
    ),
    Data = maps:get(data, Map),
    Talks = maps:get(<<"talks">>, Data),
    ?assert(is_list(Talks)),
    ?assert(Talks =/= []),
    First = hd(Talks),
    ?assertEqual(<<"Talk">>, maps:get(<<"title">>, First)),
    ?assertEqual(<<"abc123">>, maps:get(<<"youtube_id">>, First)),
    ?assert(maps:is_key(<<"languages">>, Data)),
    ?assert(maps:is_key(<<"topics">>, Data)).

speaker_year_controller_test() ->
    Req = req_bind(<<"/v1/speakers/2026/diana-pham">>, #{
        <<"year">> => <<"2026">>,
        <<"slug">> => <<"diana-pham">>
    }),
    {json, Map} = carolina_v1_controller:speaker_year(Req, fun fake/2),
    Data = maps:get(data, Map),
    ?assert(maps:get(<<"talks">>, Data) =/= []).

unknown_slug_test() ->
    {json, 404, _H, Map} = carolina_handler:handle_get(
        <<"/v1/speakers/no-such-slug">>, <<>>, fun fake/2
    ),
    ?assertEqual(<<"not_found">>, maps:get(error, Map)),
    ?assert(has(json_body({json, 404, #{}, Map}), <<"not_found">>)).

unscoped_sponsors_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/v1/sponsors">>, <<>>, fun fake/2),
    ?assert(has(json_body({json, Map}), <<"\"data\"">>)),
    ?assert(has(json_body({json, Map}), <<"flywheel">>)).

year_sponsors_test() ->
    {json, Map} = carolina_handler:handle_get(<<"/v1/sponsors">>, <<"2026">>, fun fake/2),
    Body = json_body({json, Map}),
    ?assert(has(Body, <<"tier">>)),
    ?assert(has(Body, <<"platinum">>)).

year_sponsors_controller_test() ->
    {json, Map} = carolina_v1_controller:sponsors(req(<<"/v1/sponsors">>, <<"2026">>), fun fake/2),
    ?assert(has(json_body({json, Map}), <<"tier">>)).

sponsor_detail_test() ->
    {json, Map} = carolina_handler:handle_get(
        <<"/v1/sponsors/flywheel">>, <<>>, fun fake/2
    ),
    Data = maps:get(data, Map),
    ?assertEqual(<<"flywheel">>, maps:get(<<"slug">>, Data)),
    ?assert(maps:is_key(<<"sponsorships">>, Data)).

sponsor_detail_controller_test() ->
    Req = req_bind(<<"/v1/sponsors/flywheel">>, #{<<"slug">> => <<"flywheel">>}),
    {json, Map} = carolina_v1_controller:sponsor(Req, fun fake/2),
    ?assertEqual(<<"flywheel">>, maps:get(<<"slug">>, maps:get(data, Map))).

sponsor_year_detail_test() ->
    {json, Map} = carolina_handler:handle_get(
        <<"/v1/sponsors/2026/flywheel">>, <<>>, fun fake/2
    ),
    Data = maps:get(data, Map),
    ?assertEqual(<<"platinum">>, maps:get(<<"tier">>, Data)).

sponsor_year_controller_test() ->
    Req = req_bind(<<"/v1/sponsors/2026/flywheel">>, #{
        <<"year">> => <<"2026">>,
        <<"slug">> => <<"flywheel">>
    }),
    {json, Map} = carolina_v1_controller:sponsor_year(Req, fun fake/2),
    ?assertEqual(<<"platinum">>, maps:get(<<"tier">>, maps:get(data, Map))).

unknown_sponsor_slug_test() ->
    {json, 404, _H, Map} = carolina_handler:handle_get(
        <<"/v1/sponsors/no-such-slug">>, <<>>, fun fake/2
    ),
    ?assertEqual(<<"not_found">>, maps:get(error, Map)).

unknown_year_sponsor_test() ->
    {json, 404, _H, Map} = carolina_handler:handle_get(
        <<"/v1/sponsors/2026/missing-sponsor">>, <<>>, fun fake/2
    ),
    ?assertEqual(<<"not_found">>, maps:get(error, Map)).

router_paths_test() ->
    [#{routes := Routes}] = carolina_router:routes(prod),
    Paths = [P || {P, Fun, Opts} <- Routes, is_function(Fun), is_map(Opts)],
    lists:foreach(
        fun(P) -> ?assert(lists:member(P, Paths)) end,
        [
            "/",
            "/health",
            "/v1/years",
            "/v1/speakers",
            "/v1/speakers/:slug",
            "/v1/speakers/:year/:slug",
            "/v1/sponsors",
            "/v1/sponsors/:slug",
            "/v1/sponsors/:year/:slug"
        ]
    ).
