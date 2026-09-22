-module(carolina_v1_controller).
-export([
    years/1, years/2,
    speakers/1, speakers/2,
    speaker/1, speaker/2,
    speaker_year/1, speaker_year/2,
    sponsors/1, sponsors/2,
    sponsor/1, sponsor/2,
    sponsor_year/1, sponsor_year/2
]).

years(Req) ->
    years(Req, fun carolina_catalog:query/2).

years(_Req, Catalog) ->
    carolina_handler:handle_get(<<"/v1/years">>, <<>>, Catalog).

speakers(Req) ->
    speakers(Req, fun carolina_catalog:query/2).

speakers(Req, Catalog) ->
    carolina_handler:handle_get(<<"/v1/speakers">>, carolina_handler:year_qs(Req), Catalog).

speaker(Req) ->
    speaker(Req, fun carolina_catalog:query/2).

speaker(Req, Catalog) ->
    Slug = carolina_handler:binding(Req, slug),
    carolina_handler:handle_get(<<"/v1/speakers/", Slug/binary>>, <<>>, Catalog).

speaker_year(Req) ->
    speaker_year(Req, fun carolina_catalog:query/2).

speaker_year(Req, Catalog) ->
    %% First segment is the year; :name is the speaker slug.
    Year = carolina_handler:binding(Req, slug),
    Name = carolina_handler:binding(Req, name),
    Path = iolist_to_binary([<<"/v1/speakers/">>, Year, <<"/">>, Name]),
    carolina_handler:handle_get(Path, <<>>, Catalog).

sponsors(Req) ->
    sponsors(Req, fun carolina_catalog:query/2).

sponsors(Req, Catalog) ->
    carolina_handler:handle_get(<<"/v1/sponsors">>, carolina_handler:year_qs(Req), Catalog).

sponsor(Req) ->
    sponsor(Req, fun carolina_catalog:query/2).

sponsor(Req, Catalog) ->
    Slug = carolina_handler:binding(Req, slug),
    carolina_handler:handle_get(<<"/v1/sponsors/", Slug/binary>>, <<>>, Catalog).

sponsor_year(Req) ->
    sponsor_year(Req, fun carolina_catalog:query/2).

sponsor_year(Req, Catalog) ->
    Year = carolina_handler:binding(Req, slug),
    Name = carolina_handler:binding(Req, name),
    Path = iolist_to_binary([<<"/v1/sponsors/">>, Year, <<"/">>, Name]),
    carolina_handler:handle_get(Path, <<>>, Catalog).
