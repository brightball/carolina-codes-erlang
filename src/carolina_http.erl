-module(carolina_http).
%% Nova listener config. Tests call cowboy_configuration/0 — the shipped bind.
-export([listen/0, configure_nova/0, cowboy_configuration/0]).

%% Dual-stack IPv6. Nova only forwards ip+port into cowboy:start_clear;
%% Linux treats {0,0,0,0,0,0,0,0} as dual-stack when ipv6_v6only is false.
cowboy_configuration() ->
    #{
        port => carolina:port(),
        ip => {0, 0, 0, 0, 0, 0, 0, 0},
        ipv6_v6only => false
    }.

configure_nova() ->
    _ = application:load(nova),
    application:set_env(nova, bootstrap_application, carolina),
    application:set_env(nova, cowboy_configuration, cowboy_configuration()),
    application:set_env(nova, use_sessions, false),
    application:set_env(nova, render_error_pages, false),
    application:set_env(nova, environment, prod),
    ok.

listen() ->
    ok = configure_nova(),
    case application:ensure_all_started(nova) of
        {ok, _} -> ok;
        {error, {already_started, nova}} -> ok;
        {error, Reason} -> error({nova_listen, Reason})
    end.
