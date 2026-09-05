-module(carolina_json).
-export([encode/1, row/1, tags/2, as_int/1, as_bool/1, as_tags/1]).

encode(Term) ->
    iolist_to_binary(thoas:encode(Term)).

row(Map) when is_map(Map) ->
    maps:from_list([{K, encode_val(K, V)} || {K, V} <- maps:to_list(Map)]).

encode_val(<<"featured">>, V) -> as_bool(V);
encode_val(<<"year">>, V) -> as_int(V);
encode_val(<<"languages">>, V) -> as_tags(V);
encode_val(<<"topics">>, V) -> as_tags(V);
encode_val(<<"talks">>, V) when is_list(V) -> [row(T) || T <- V];
encode_val(<<"sponsorships">>, V) when is_list(V) -> [row(T) || T <- V];
encode_val(_K, null) -> null;
encode_val(_K, undefined) -> null;
encode_val(_K, V) when is_binary(V) -> V;
encode_val(_K, V) when is_integer(V) -> V;
encode_val(_K, V) when is_float(V) -> V;
encode_val(_K, V) when is_boolean(V) -> V;
encode_val(_K, V) when is_list(V) ->
    case io_lib:printable_list(V) of
        true -> unicode:characters_to_binary(V);
        false -> V
    end;
encode_val(_K, V) -> iolist_to_binary(io_lib:format("~p", [V])).

tags(Talks, Key) ->
    unique(lists:append([as_tags(maps:get(Key, T, [])) || T <- Talks])).

as_tags(null) -> [];
as_tags(undefined) -> [];
as_tags(L) when is_list(L) ->
    case L =/= [] andalso is_integer(hd(L)) of
        true -> as_tags(unicode:characters_to_binary(L));
        false -> [tag_item(X) || X <- L, tag_item(X) =/= <<>>]
    end;
as_tags(B) when is_binary(B) ->
    S = string:trim(B),
    case S of
        <<>> -> [];
        <<"[]">> -> [];
        <<"{}">> -> [];
        <<"null">> -> [];
        <<"[", Rest/binary>> ->
            Inner = strip_right(Rest, $]),
            [tag_item(P) || P <- binary:split(Inner, <<",">>, [global]), tag_item(P) =/= <<>>];
        <<"{", Rest/binary>> ->
            Inner = strip_right(Rest, $}),
            [tag_item(P) || P <- binary:split(Inner, <<",">>, [global]), tag_item(P) =/= <<>>];
        _ -> [S]
    end;
as_tags(_) -> [].

tag_item(null) -> <<>>;
tag_item(B) when is_binary(B) ->
    string:trim(B, both, [$\s, $\t, $", $']);
tag_item(L) when is_list(L) -> tag_item(unicode:characters_to_binary(L));
tag_item(A) when is_atom(A) -> atom_to_binary(A, utf8);
tag_item(_) -> <<>>.

strip_right(Bin, Ch) ->
    case byte_size(Bin) of
        0 -> Bin;
        N ->
            case binary:at(Bin, N - 1) of
                Ch -> binary:part(Bin, 0, N - 1);
                _ -> Bin
            end
    end.

as_int(I) when is_integer(I) -> I;
as_int(B) when is_binary(B) ->
    case string:to_integer(string:trim(B)) of
        {N, _} when is_integer(N) -> N;
        _ -> 0
    end;
as_int(L) when is_list(L) -> as_int(list_to_binary(L));
as_int(_) -> 0.

as_bool(true) -> true;
as_bool(false) -> false;
as_bool(1) -> true;
as_bool(0) -> false;
as_bool(<<"t">>) -> true;
as_bool(<<"true">>) -> true;
as_bool(<<"1">>) -> true;
as_bool("t") -> true;
as_bool("true") -> true;
as_bool(_) -> false.

unique(List) ->
    lists:reverse(
        lists:foldl(
            fun(X, Acc) ->
                case lists:member(X, Acc) of
                    true -> Acc;
                    false -> [X | Acc]
                end
            end,
            [],
            List
        )
    ).
