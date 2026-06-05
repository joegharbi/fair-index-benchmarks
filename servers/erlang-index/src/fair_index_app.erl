-module(fair_index_app).
-behaviour(application).
-export([start/2, stop/1]).

start(_Type, _Args) ->
    fair_index_sup:start_link().

stop(_State) ->
    ok.
