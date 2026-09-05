-module(carolina_handler_tests).
%% Drive shipped carolina_handler:handle_get/3 — not a reimplementation.
-include_lib("eunit/include/eunit.hrl").

has(Body, Sub) ->
    binary:match(iolist_to_binary(Body), iolist_to_binary(Sub)) =/= nomatch.

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
        false -> pick_speakers(Sql, Arg1)
    end.

pick_speakers(Sql, Arg1) ->
    case has(Sql, <<"v1_speakers">>) of
        true -> [speaker()];
        false -> pick_talks(Sql, Arg1)
    end.

pick_talks(Sql, Arg1) ->
    case has(Sql, <<"v1_talks">>) of
        true -> [talk()];
        false -> pick_year_sponsors(Sql, Arg1)
    end.

pick_year_sponsors(Sql, Arg1) ->
    case has(Sql, <<"v1_year_sponsors">>) of
        true ->
            case Arg1 of
                <<"missing-sponsor">> -> [];
                _ -> [year_sponsor()]
            end;
        false -> pick_sponsors_slug(Sql)
    end.

pick_sponsors_slug(Sql) ->
    case has(Sql, <<"v1_sponsors WHERE slug">>) of
        true -> [];
        false -> pick_sponsors(Sql)
    end.

pick_sponsors(Sql) ->
    case has(Sql, <<"v1_sponsors">>) of
        true -> [year_sponsor()];
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
to_bin(L) when is_list(L) -> list_to_binary(L).

health_test() ->
    {200, Body} = carolina_handler:handle_get(<<"/health">>, <<>>, fun fake/2),
    ?assert(has(Body, <<"\"status\"">>)),
    ?assert(has(Body, <<"\"ok\"">>)).

health_slash_test() ->
    {200, Body} = carolina_handler:handle_get(<<"/health/">>, <<>>, fun fake/2),
    ?assert(has(Body, <<"ok">>)).

identity_test() ->
    {200, Body} = carolina_handler:handle_get(<<"/">>, <<>>, fun fake/2),
    ?assert(has(Body, <<"Erlang">>)),
    ?assert(has(Body, <<"Cowboy">>)),
    ?assertNot(has(Body, <<"Gleam">>)),
    ?assertNot(has(Body, <<"mist">>)).

unknown_slug_test() ->
    {404, Body} = carolina_handler:handle_get(
        <<"/v1/speakers/no-such-slug">>, <<>>, fun fake/2
    ),
    ?assert(has(Body, <<"not_found">>)).

year_speakers_test() ->
    put(sqls, []),
    {200, Body} = carolina_handler:handle_get(<<"/v1/speakers">>, <<"2026">>, fun fake/2),
    ?assert(has(Body, <<"\"data\"">>)),
    ?assert(has(Body, <<"languages">>)),
    ?assert(has(Body, <<"topics">>)),
    ?assert(has(Body, <<"php">>)),
    ?assert(has(Body, <<"development">>)),
    Sqls = get(sqls),
    ?assert(lists:any(fun(S) -> has(S, <<"v1_talks">>) end, Sqls)),
    ?assertNot(lists:any(fun(S) -> has(S, <<"v1_year_speakers">>) end, Sqls)).

speaker_year_detail_test() ->
    {200, Body} = carolina_handler:handle_get(
        <<"/v1/speakers/2026/diana-pham">>, <<>>, fun fake/2
    ),
    {ok, Dec} = thoas:decode(Body),
    Data = maps:get(<<"data">>, Dec),
    Talks = maps:get(<<"talks">>, Data),
    ?assert(is_list(Talks)),
    ?assert(Talks =/= []),
    First = hd(Talks),
    ?assertEqual(<<"Talk">>, maps:get(<<"title">>, First)),
    ?assertEqual(<<"abc123">>, maps:get(<<"youtube_id">>, First)).

year_sponsors_test() ->
    {200, Body} = carolina_handler:handle_get(<<"/v1/sponsors">>, <<"2026">>, fun fake/2),
    ?assert(has(Body, <<"tier">>)),
    ?assert(has(Body, <<"platinum">>)).

years_test() ->
    {200, Body} = carolina_handler:handle_get(<<"/v1/years">>, <<>>, fun fake/2),
    ?assert(has(Body, <<"\"data\"">>)).
