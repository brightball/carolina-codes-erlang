-module(quality_gates_tests).
%% Guard committed Makefile, pre-commit, and Gitea workflow wiring.
%% Does not reimplement the scanners; those run via make / pre-commit / Gitea.
-include_lib("eunit/include/eunit.hrl").

root() ->
    filename:absname(filename:join(filename:dirname(?FILE), "..")).

read(Rel) ->
    {ok, Bin} = file:read_file(filename:join(root(), Rel)),
    Bin.

has(Bin, Sub) ->
    binary:match(Bin, iolist_to_binary(Sub)) =/= nomatch.

makefile_exposes_five_checks_test() ->
    Make = read("Makefile"),
    lists:foreach(
        fun(T) ->
            ?assertEqual(true, has(Make, T))
        end,
        [
            "\ntest:",
            "\nsast:",
            "\naudit:",
            "\nsecrets:",
            "\nlint:",
            "$(GITLEAKS) detect --source"
        ]
    ).

precommit_names_gitleaks_and_five_checks_test() ->
    Y = read(".pre-commit-config.yaml"),
    lists:foreach(
        fun(T) ->
            ?assertEqual(true, has(Y, T))
        end,
        [
            "id: local-tests",
            "id: sast",
            "id: audit",
            "id: gitleaks",
            "name: gitleaks",
            "entry: make secrets",
            "id: elvis"
        ]
    ).

githook_invokes_real_precommit_test() ->
    Hook = read(".githooks/pre-commit"),
    ?assertEqual(true, has(Hook, "pre-commit run --hook-stage pre-commit --all-files")),
    ?assertEqual(true, has(Hook, "make secrets")).

gitea_jobs_are_parallel_and_call_make_test() ->
    Y = read(".gitea/workflows/ci.yml"),
    lists:foreach(
        fun(Job) ->
            Needle = iolist_to_binary(["  ", Job, ":\n"]),
            ?assertEqual(true, has(Y, Needle))
        end,
        [<<"test">>, <<"sast">>, <<"audit">>, <<"gitleaks">>, <<"lint">>]
    ),
    ?assertEqual(false, has(Y, "needs:")),
    ?assertEqual(true, has(Y, "make test")),
    ?assertEqual(true, has(Y, "make sast")),
    ?assertEqual(true, has(Y, "make audit")),
    ?assertEqual(true, has(Y, "make secrets")),
    ?assertEqual(true, has(Y, "make lint")),
    ?assertEqual(false, has(Y, "git init")),
    ?assertEqual(false, has(Y, "uses: actions/checkout")),
    ?assertEqual(true, has(Y, "x-access-token")).
