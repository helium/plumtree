-module(plumtree).

-export([start/0, stop/0]).

start() ->
    application:ensure_all_started(plumtree).

stop() ->
    application:stop(plumtree).
