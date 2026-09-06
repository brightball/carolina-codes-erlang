-module(carolina_main_controller).
-export([index/1, index/2, health/1, health/2]).

index(Req) ->
    index(Req, fun carolina_catalog:query/2).

index(_Req, Catalog) ->
    carolina_handler:handle_get(<<"/">>, <<>>, Catalog).

health(Req) ->
    health(Req, fun carolina_catalog:query/2).

health(_Req, Catalog) ->
    carolina_handler:handle_get(<<"/health">>, <<>>, Catalog).
