-module(carolina_router).
-behaviour(nova_router).
-export([routes/1]).

routes(_Environment) ->
    [#{
        prefix => "",
        security => false,
        routes => [
            {"/", fun carolina_main_controller:index/1, #{methods => [get]}},
            {"/health", fun carolina_main_controller:health/1, #{methods => [get]}},
            {"/v1/years", fun carolina_v1_controller:years/1, #{methods => [get]}},
            {"/v1/speakers", fun carolina_v1_controller:speakers/1, #{methods => [get]}},
            %% routing_tree commits to the first binding and does not try
            %% the next sibling. Sharing the first name nests the long URL
            %% under the short one. Public path is still /<year>/<slug>.
            {"/v1/speakers/:slug/:name",
             fun carolina_v1_controller:speaker_year/1,
             #{methods => [get]}},
            {"/v1/speakers/:slug", fun carolina_v1_controller:speaker/1, #{methods => [get]}},
            {"/v1/sponsors", fun carolina_v1_controller:sponsors/1, #{methods => [get]}},
            {"/v1/sponsors/:slug/:name",
             fun carolina_v1_controller:sponsor_year/1,
             #{methods => [get]}},
            {"/v1/sponsors/:slug", fun carolina_v1_controller:sponsor/1, #{methods => [get]}}
        ]
    }].
