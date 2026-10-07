-module(quality_gates_tests).
%% Guard committed Makefile, pre-commit, and Gitea workflow wiring.
%% Does not reimplement the scanners; those run via make / pre-commit / Gitea.
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/file.hrl").

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

check_jobs() ->
    [<<"test">>, <<"sast">>, <<"audit">>, <<"gitleaks">>, <<"lint">>].

check_make() ->
    #{
        <<"test">> => <<"make test">>,
        <<"sast">> => <<"make sast">>,
        <<"audit">> => <<"make audit">>,
        <<"gitleaks">> => <<"make secrets">>,
        <<"lint">> => <<"make lint">>
    }.

gitea_jobs(Yaml) ->
    case binary:split(Yaml, <<"\njobs:">>) of
        [_, Rest] -> parse_jobs(binary:split(Rest, <<"\n">>, [global]), <<>>, <<>>, #{});
        _ -> #{}
    end.

parse_jobs([], Current, Acc, Map) ->
    flush_job(Current, Acc, Map);
parse_jobs([Line | Rest], Current, Acc, Map) ->
    case job_header(Line) of
        {ok, Name} ->
            parse_jobs(Rest, Name, <<>>, flush_job(Current, Acc, Map));
        false ->
            parse_jobs(Rest, Current, <<Acc/binary, Line/binary, "\n">>, Map)
    end.

job_header(<<"  ", Rest/binary>>) ->
    case Rest of
        <<" ", _/binary>> -> false;
        _ ->
            case binary:match(Rest, <<":">>) of
                {0, _} -> false;
                {Pos, 1} ->
                    Name = binary:part(Rest, 0, Pos),
                    After = binary:part(Rest, Pos + 1, byte_size(Rest) - Pos - 1),
                    case {Name, After} of
                        {<<>>, _} -> false;
                        {_, <<>>} ->
                            case binary:match(Name, <<" ">>) of
                                nomatch -> {ok, Name};
                                _ -> false
                            end;
                        {_, <<"\n">>} -> {ok, Name};
                        _ -> false
                    end;
                nomatch -> false;
                _ -> false
            end
    end;
job_header(_) ->
    false.

flush_job(<<>>, _, Map) ->
    Map;
flush_job(Name, Acc, Map) ->
    Map#{Name => Acc}.

job_source(Body) ->
    iolist_to_binary([Body, helper_sources(Body)]).

helper_sources(Body) ->
    case re:run(Body, <<"tools/[A-Za-z0-9._/-]+\\.sh">>, [global, {capture, all, binary}]) of
        nomatch -> <<>>;
        {match, Matches} ->
            Paths = lists:usort([P || [P] <- Matches]),
            [read(binary_to_list(P)) || P <- Paths]
    end.

job_needs(Body, Name) ->
    has(Body, iolist_to_binary(["needs: ", Name])).

%% Gitea 1.24.7 rejects YAML anchors/aliases when splitting jobs (unknown anchor).
%% Match &name / *name, not bash && or 2>&1.
has_yaml_anchor_or_alias(Bin) ->
    re:run(Bin, <<"[&*][A-Za-z_][A-Za-z0-9_-]*">>, [{capture, none}]) =/= nomatch.

gitea_prepare_then_check_jobs_test() ->
    Y = read(".gitea/workflows/ci.yml"),
    Jobs = gitea_jobs(Y),
    lists:foreach(
        fun(Job) ->
            ?assertEqual({Job, true}, {Job, maps:is_key(Job, Jobs)})
        end,
        [<<"prepare">> | check_jobs()]
    ),
    Prepare = maps:get(<<"prepare">>, Jobs),
    PrepareSrc = job_source(Prepare),
    ?assertEqual(true, has(PrepareSrc, "git clone")),
    ?assertEqual(true, has(PrepareSrc, "GITHUB_SHA")),
    ?assertEqual(true, has(PrepareSrc, "x-access-token")),
    ?assertEqual(true, has(PrepareSrc, "apt-get install")),
    ?assertEqual(true, has(PrepareSrc, "rebar3/releases/download/3.25.1/rebar3")),
    ?assertEqual(true, has(PrepareSrc, "gitleaks_8.30.1_linux_x64.tar.gz")),
    ?assertEqual(true, has(Prepare, "ci-env.sh prepare")),
    ?assertEqual(false, job_needs(Prepare, "test")),
    lists:foreach(
        fun(Cmd) ->
            ?assertEqual({Cmd, false}, {Cmd, has(Prepare, Cmd)})
        end,
        [<<"make test">>, <<"make sast">>, <<"make audit">>, <<"make secrets">>, <<"make lint">>]
    ),
    Makes = check_make(),
    lists:foreach(
        fun(Job) ->
            Body = maps:get(Job, Jobs),
            Cmd = maps:get(Job, Makes),
            ?assertEqual({Job, true}, {Job, job_needs(Body, <<"prepare">>)}),
            lists:foreach(
                fun(Other) ->
                    ?assertEqual(
                        {Job, Other, false},
                        {Job, Other, job_needs(Body, Other)}
                    )
                end,
                check_jobs() -- [Job]
            ),
            ?assertEqual({Job, Cmd, true}, {Job, Cmd, has(Body, Cmd)}),
            ?assertEqual(
                {Job, restore, true},
                {Job, restore, has(Body, "ci-env.sh restore")}
            ),
            ?assertEqual({Job, apt, false}, {Job, apt, has(Body, "apt-get")}),
            ?assertEqual({Job, clone, false}, {Job, clone, has(Body, "git clone")}),
            ?assertEqual(
                {Job, rebar3, false},
                {Job, rebar3, has(Body, "rebar3/releases")}
            ),
            ?assertEqual(
                {Job, gitleaks, false},
                {Job, gitleaks, has(Body, "gitleaks_8.30.1_linux")}
            ),
            ?assertEqual(
                {Job, gitleaks_dl, false},
                {Job, gitleaks_dl, has(Body, "gitleaks/releases")}
            )
        end,
        check_jobs()
    ),
    ?assertEqual(true, has(Y, "ci-env.sh restore")),
    ?assertEqual(false, has_yaml_anchor_or_alias(Y)),
    ?assertEqual(true, has(read("Makefile"), "env -u GITHUB_TOKEN")),
    ?assertEqual(false, has(Y, "git init")),
    ?assertEqual(false, has(Y, "init.defaultBranch")),
    ?assertEqual(false, has(Y, "uses: actions/checkout")),
    ?assertEqual(false, maps:is_key(<<"dialyzer">>, Jobs)).

%% README versions are whatever rebar.config and Dockerfile say.
%% The digits are not hardcoded here.
readme_pins_tree_versions_test() ->
    {ok, Terms} = file:consult(filename:join(root(), "rebar.config")),
    Deps = proplists:get_value(deps, Terms),
    Readme = read("README.md"),
    lists:foreach(
        fun(Name) ->
            Vsn = dep_vsn(Deps, Name),
            ?assertEqual({Name, true}, {Name, has(Readme, atom_to_list(Name))}),
            ?assertEqual({Name, Vsn, true}, {Name, Vsn, has(Readme, Vsn)})
        end,
        [nova, epgsql, thoas]
    ),
    Majors = erlang_image_majors(read("Dockerfile")),
    Unique = lists:usort(Majors),
    ?assertMatch([_], Unique),
    [Major] = Unique,
    ?assertEqual(true, has(Readme, ["erlang:", Major])),
    ReadmeMajors = erlang_image_majors(Readme),
    ?assertEqual(true, ReadmeMajors =/= []),
    lists:foreach(
        fun(Found) ->
            ?assertEqual(Major, Found)
        end,
        ReadmeMajors
    ),
    Min = proplists:get_value(minimum_otp_vsn, Terms),
    ?assertEqual(true, is_list(Min) andalso Min =/= ""),
    ?assertEqual(true, has(Readme, "minimum_otp_vsn")),
    ?assertEqual(true, has(Readme, Min)).

dep_vsn(Deps, Name) ->
    case lists:keyfind(Name, 1, Deps) of
        {Name, Vsn} when is_list(Vsn) ->
            case re:run(Vsn, "^[0-9]+\\.[0-9]+\\.[0-9]+$", [{capture, none}]) of
                match -> Vsn;
                nomatch -> erlang:error({bad_dep_vsn, Name, Vsn})
            end;
        Other ->
            erlang:error({missing_dep, Name, Other})
    end.

erlang_image_majors(Bin) ->
    case re:run(Bin, <<"erlang:([0-9]+)">>, [global, {capture, all, binary}]) of
        {match, Matches} -> [Major || [_, Major] <- Matches];
        nomatch -> []
    end.

gitea_rejects_yaml_anchors_test() ->
    ?assertEqual(true, has_yaml_anchor_or_alias(<<"  - *restore-prepared-env\n">>)),
    ?assertEqual(true, has_yaml_anchor_or_alias(<<"x-restore: &restore-prepared-env\n">>)),
    ?assertEqual(false, has_yaml_anchor_or_alias(<<"apt-get update && apt-get install -y git\n">>)),
    ?assertEqual(false, has_yaml_anchor_or_alias(<<"curl -fsSL url 2>&1\n">>)),
    ?assertEqual(false, has_yaml_anchor_or_alias(read(".gitea/workflows/ci.yml"))).

ci_env_pack_restore_roundtrip_test() ->
    Root = make_temp_dir(),
    try
        Ws = filename:join(Root, "ws"),
        Bin = filename:join(Root, "bin"),
        ok = file:make_dir(Ws),
        ok = file:make_dir(Bin),
        ok = file:write_file(
            filename:join(Ws, "hello.txt"),
            <<"carolina-codes-erlang\n">>
        ),
        write_exec(filename:join(Bin, "rebar3"), <<"#!/bin/sh\necho rebar3\n">>),
        write_exec(filename:join(Bin, "gitleaks"), <<"#!/bin/sh\necho gitleaks\n">>),
        Tar = filename:join(Root, "prepared-env.tar.gz"),
        run_ci_env("pack", [
            {"GITHUB_WORKSPACE", Ws},
            {"CI_ENV_BIN", Bin},
            {"CI_ENV_TAR", Tar}
        ]),
        ?assertEqual(true, filelib:is_regular(Tar)),
        Ws2 = filename:join(Root, "ws2"),
        Bin2 = filename:join(Root, "bin2"),
        ok = file:make_dir(Ws2),
        ok = file:make_dir(Bin2),
        run_ci_env("unpack", [
            {"GITHUB_WORKSPACE", Ws2},
            {"CI_ENV_BIN", Bin2},
            {"CI_ENV_TAR", Tar}
        ]),
        {ok, Hello} = file:read_file(filename:join(Ws2, "hello.txt")),
        ?assertEqual(<<"carolina-codes-erlang\n">>, Hello),
        assert_exec(filename:join(Bin2, "rebar3"), <<"#!/bin/sh\necho rebar3\n">>),
        assert_exec(filename:join(Bin2, "gitleaks"), <<"#!/bin/sh\necho gitleaks\n">>)
    after
        os:cmd("rm -rf " ++ quote(Root))
    end.

write_exec(Path, Body) ->
    ok = file:write_file(Path, Body),
    ok = file:change_mode(Path, 8#755).

assert_exec(Path, Body) ->
    {ok, Got} = file:read_file(Path),
    ?assertEqual(Body, Got),
    {ok, Info} = file:read_file_info(Path),
    Mode = Info#file_info.mode,
    ?assertEqual({Path, true}, {Path, (Mode band 8#111) =/= 0}).

make_temp_dir() ->
    Base =
        case os:getenv("TMPDIR") of
            false -> "/tmp";
            "" -> "/tmp";
            Dir -> Dir
        end,
    Path = filename:join(
        Base,
        "ci-env-" ++ integer_to_list(erlang:unique_integer([positive]))
    ),
    ok = file:make_dir(Path),
    Path.

quote(Path) ->
    "'" ++ lists:flatten(string:replace(Path, "'", "'\\''", all)) ++ "'".

run_ci_env(Cmd, Env) ->
    Helper = filename:join(root(), "tools/ci-env.sh"),
    Port = open_port(
        {spawn_executable, "/bin/bash"},
        [
            {args, [Helper, Cmd]},
            {env, Env},
            stderr_to_stdout,
            exit_status,
            binary,
            hide
        ]
    ),
    gather_port(Port, <<>>).

gather_port(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            gather_port(Port, <<Acc/binary, Data/binary>>);
        {Port, {exit_status, 0}} ->
            Acc;
        {Port, {exit_status, Status}} ->
            erlang:error({ci_env_exit, Status, Acc})
    after 30000 ->
        erlang:error({ci_env_timeout, Acc})
    end.
