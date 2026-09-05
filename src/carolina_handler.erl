-module(carolina_handler).
%% Shipped GET router. Tests call handle_get/3 with a fake catalog.
-export([handle_get/2, handle_get/3]).

-define(SPEAKER_COLS,
    "slug, first_name, last_name, name, tagline, bio, company, location, "
    "photo_path, twitter_url, linkedin_url, website_url, github_url, featured").
-define(YEAR_SPONSOR_COLS,
    "slug, name, website, logo_path, description, blurb, tier, featured, year, "
    "twitter_url, linkedin_url, youtube_url, instagram_url, facebook_url").
-define(SPONSOR_COLS,
    "slug, name, website, logo_path, description, twitter_url, linkedin_url, "
    "youtube_url, instagram_url, facebook_url").
-define(TALK_COLS,
    "slug, title, description, format, youtube_id, year, speaker_slug, "
    "languages, topics").

handle_get(Path, Year) ->
    handle_get(Path, Year, fun carolina_catalog:query/2).

handle_get(Path0, Year0, Catalog) ->
    Path = normalize(to_bin(Path0)),
    Year = to_bin(Year0),
    Parts = split(Path),
    route(Path, Parts, Year, Catalog).

route(<<"/health">>, _P, _Y, _C) ->
    {200, carolina_json:encode(#{status => <<"ok">>})};
route(<<"/">>, _P, _Y, _C) ->
    {200, carolina_identity:json()};
route(<<"/v1/years">>, _P, _Y, C) ->
    Rows = C(
        <<"SELECT year, slug, name, status FROM v1_years ORDER BY year DESC">>,
        []
    ),
    {200, wrap(Rows)};
route(<<"/v1/speakers">>, _P, Year, C) ->
    {200, wrap(list_speakers(Year, C))};
route(<<"/v1/sponsors">>, _P, Year, C) ->
    {200, wrap(list_sponsors(Year, C))};
route(_Path, [<<"v1">>, <<"speakers">>, Y, Slug], _Year, C) ->
    case is_year(Y) of
        true -> speaker_year(Y, Slug, C);
        false -> not_found()
    end;
route(_Path, [<<"v1">>, <<"speakers">>, Slug], _Year, C) ->
    speaker_detail(Slug, C);
route(_Path, [<<"v1">>, <<"sponsors">>, Y, Slug], _Year, C) ->
    case is_year(Y) of
        true -> sponsor_year(Y, Slug, C);
        false -> not_found()
    end;
route(_Path, [<<"v1">>, <<"sponsors">>, Slug], _Year, C) ->
    sponsor_detail(Slug, C);
route(_, _, _, _) ->
    not_found().

list_speakers(<<>>, C) ->
    C(
        <<"SELECT ", ?SPEAKER_COLS, " FROM v1_speakers ORDER BY last_name, first_name">>,
        []
    );
list_speakers(Year, C) ->
    Speakers = C(
        <<"SELECT ", ?SPEAKER_COLS,
          " FROM v1_speakers WHERE slug IN"
          " (SELECT speaker_slug FROM v1_talks WHERE year = $1)"
          " ORDER BY last_name, first_name">>,
        [Year]
    ),
    Talks = C(
        <<"SELECT ", ?TALK_COLS,
          " FROM v1_talks WHERE year = $1 ORDER BY speaker_slug, year DESC">>,
        [Year]
    ),
    [merge_year_speaker(Sp, Talks, Year) || Sp <- Speakers].

list_sponsors(<<>>, C) ->
    C(
        <<"SELECT ", ?SPONSOR_COLS, " FROM v1_sponsors ORDER BY name">>,
        []
    );
list_sponsors(Year, C) ->
    C(
        <<"SELECT ", ?YEAR_SPONSOR_COLS,
          " FROM v1_year_sponsors WHERE year = $1 ORDER BY name">>,
        [Year]
    ).

speaker_detail(Slug, C) ->
    case C(
        <<"SELECT ", ?SPEAKER_COLS, " FROM v1_speakers WHERE slug = $1">>,
        [Slug]
    ) of
        [] ->
            not_found();
        [Sp | _] ->
            Talks = C(
                <<"SELECT ", ?TALK_COLS,
                  " FROM v1_talks WHERE speaker_slug = $1 ORDER BY year DESC">>,
                [Slug]
            ),
            {200, wrap(Sp#{<<"talks">> => Talks})}
    end.

speaker_year(Year, Slug, C) ->
    case C(
        <<"SELECT ", ?SPEAKER_COLS, " FROM v1_speakers WHERE slug = $1">>,
        [Slug]
    ) of
        [] ->
            not_found();
        [Sp | _] ->
            Talks = C(
                <<"SELECT ", ?TALK_COLS,
                  " FROM v1_talks WHERE speaker_slug = $1 AND year = $2"
                  " ORDER BY year DESC">>,
                [Slug, Year]
            ),
            case Talks of
                [] -> not_found();
                _ -> {200, wrap(merge_year_speaker(Sp, Talks, Year))}
            end
    end.

sponsor_detail(Slug, C) ->
    case C(
        <<"SELECT ", ?SPONSOR_COLS, " FROM v1_sponsors WHERE slug = $1">>,
        [Slug]
    ) of
        [] -> not_found();
        [Sp | _] ->
            Sps = C(
                <<"SELECT * FROM v1_sponsorships WHERE sponsor_slug = $1">>,
                [Slug]
            ),
            {200, wrap(Sp#{<<"sponsorships">> => Sps})}
    end.

sponsor_year(Year, Slug, C) ->
    case C(
        <<"SELECT ", ?YEAR_SPONSOR_COLS,
          " FROM v1_year_sponsors WHERE year = $1 AND slug = $2">>,
        [Year, Slug]
    ) of
        [] -> not_found();
        [Sp | _] -> {200, wrap(Sp)}
    end.

merge_year_speaker(Sp, Talks, Year) ->
    Slug = maps:get(<<"slug">>, Sp, <<>>),
    Mine = [T || T <- Talks, maps:get(<<"speaker_slug">>, T, <<>>) =:= Slug],
    Sp#{
        <<"year">> => carolina_json:as_int(Year),
        <<"talks">> => Mine,
        <<"languages">> => carolina_json:tags(Mine, <<"languages">>),
        <<"topics">> => carolina_json:tags(Mine, <<"topics">>)
    }.

wrap(Rows) when is_list(Rows) ->
    carolina_json:encode(#{data => [carolina_json:row(R) || R <- Rows]});
wrap(Row) when is_map(Row) ->
    carolina_json:encode(#{data => carolina_json:row(Row)}).

not_found() ->
    {404, carolina_json:encode(#{error => <<"not_found">>})}.

normalize(<<>>) -> <<"/">>;
normalize(<<"/">>) -> <<"/">>;
normalize(Path) ->
    case binary:last(Path) of
        $/ -> binary:part(Path, 0, byte_size(Path) - 1);
        _ -> Path
    end.

split(<<"/">>) -> [];
split(Path) ->
    [P || P <- binary:split(Path, <<"/">>, [global]), P =/= <<>>].

is_year(<<>>) -> false;
is_year(Bin) ->
    lists:all(fun(C) -> C >= $0 andalso C =< $9 end, binary_to_list(Bin)).

to_bin(B) when is_binary(B) -> B;
to_bin(L) when is_list(L) -> list_to_binary(L);
to_bin(undefined) -> <<>>;
to_bin(null) -> <<>>.
