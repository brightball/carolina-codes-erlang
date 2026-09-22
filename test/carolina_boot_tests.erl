-module(carolina_boot_tests).
%% Shipped boot, bind, Fly suspend policy, and the quality checks on
%% the paths Gitea already runs.
-include_lib("eunit/include/eunit.hrl").

root() ->
    filename:absname(filename:join(filename:dirname(?FILE), "..")).

read(Rel) ->
    {ok, Bin} = file:read_file(filename:join(root(), Rel)),
    Bin.

has(Bin, Sub) ->
    binary:match(Bin, iolist_to_binary(Sub)) =/= nomatch.

ipv6_dual_stack_and_port_test() ->
    Prev = os:getenv("PORT"),
    os:putenv("PORT", "9099"),
    try
        ?assertEqual(9099, carolina:port()),
        Cfg = carolina_http:cowboy_configuration(),
        ?assertEqual(9099, maps:get(port, Cfg)),
        ?assertEqual({0, 0, 0, 0, 0, 0, 0, 0}, maps:get(ip, Cfg)),
        ?assertEqual(false, maps:get(ipv6_v6only, Cfg))
    after
        restore_port(Prev)
    end.

unset_port_defaults_to_4028_test() ->
    Prev = os:getenv("PORT"),
    os:unsetenv("PORT"),
    try
        ?assertEqual(4028, carolina:port())
    after
        restore_port(Prev)
    end.

restore_port(false) ->
    os:unsetenv("PORT");
restore_port("") ->
    os:unsetenv("PORT");
restore_port(Port) ->
    os:putenv("PORT", Port).

vm_args_one_scheduler_test() ->
    Args = read("config/vm.args"),
    ?assertEqual(true, has(Args, "+S 1:1")),
    ?assertEqual(true, has(Args, "+SDcpu 1:1")),
    ?assertEqual(true, has(Args, "+SDio 1:1")),
    ?assertEqual(true, has(Args, "+sbwt none")),
    ?assertEqual(true, has(Args, "+sbwtdcpu none")),
    ?assertEqual(true, has(Args, "+sbwtdio none")),
    Server = read("bin/server"),
    ?assertEqual(true, has(Server, "-args_file")),
    ?assertEqual(true, has(Server, "config/vm.args")),
    ?assertEqual(false, has(Server, "rebar3")),
    ?assertEqual(false, has(Server, "erlc")).

schedulers_online_test_() ->
    {timeout, 60, fun schedulers_online/0}.

schedulers_online() ->
    Args = filename:join(root(), "config/vm.args"),
    Eval =
        "io:format(\"schedulers_online=~p~n\", "
        "[erlang:system_info(schedulers_online)]), halt().",
    Cmd = lists:flatten(io_lib:format(
        "erl -args_file \"~s\" -noshell -eval '~s'",
        [Args, Eval]
    )),
    Out = os:cmd(Cmd),
    ?assertEqual(match, re:run(Out, "schedulers_online=1\\n", [{capture, none}])).

fly_suspends_at_256mb_test() ->
    Fly = read("fly.toml"),
    ?assertEqual(true, has(Fly, "auto_stop_machines = \"suspend\"")),
    ?assertEqual(true, has(Fly, "auto_start_machines = true")),
    ?assertEqual(true, has(Fly, "min_machines_running = 0")),
    ?assertEqual(true, has(Fly, "memory = \"256mb\"")),
    ?assertEqual(true, has(Fly, "cpu_kind = \"shared\"")),
    ?assertEqual(true, has(Fly, "cpus = 1")),
    ?assertEqual(true, has(Fly, "PORT = \"8080\"")),
    ?assertEqual(false, has(Fly, "auto_stop_machines = \"stop\"")),
    ?assertEqual(false, has(Fly, "min_machines_running = 1")).

entrypoint_does_not_compile_test() ->
    Docker = read("Dockerfile"),
    Parts = binary:split(Docker, <<"\nFROM ">>, [global]),
    Runtime = lists:last(Parts),
    ?assertEqual(true, has(Docker, "rebar3 as prod compile")),
    ?assertEqual(true, has(Runtime, "rm -f /usr/local/bin/rebar3")),
    ?assertEqual(false, has(Runtime, "rebar3 as")),
    ?assertEqual(false, has(Runtime, "curl")),
    ?assertEqual(false, has(Runtime, "compile")),
    ?assertEqual(true, has(Runtime, "CMD [\"/app/bin/server\"]")),
    ?assertEqual(true, has(Runtime, "COPY --from=build")),
    ?assertEqual(false, has(Runtime, "COPY src")).

otp_27_image_matches_ci_test() ->
    Docker = read("Dockerfile"),
    Ci = read(".gitea/workflows/ci.yml"),
    ?assertEqual(true, has(Docker, "erlang:27-slim")),
    ?assertEqual(true, has(Ci, "image: docker.io/library/erlang:27-slim")),
    ?assertEqual(false, has(Docker, "erlang:29")),
    ?assertEqual(false, has(Ci, "erlang:29")).

warnings_and_xref_on_test_path_test() ->
    Rebar = read("rebar.config"),
    Make = read("Makefile"),
    ?assertEqual(true, has(Rebar, "warnings_as_errors")),
    ?assertEqual(true, has(Rebar, "undefined_function_calls")),
    ?assertEqual(true, has(Rebar, "undefined_functions")),
    ?assertEqual(true, has(Make, "$(REBAR) xref")),
    ?assertEqual(true, has(Make, "eunit: compile xref")),
    ?assertEqual(false, has(read(".gitea/workflows/ci.yml"), "\n  dialyzer:")).
