-module(plumtree).

-export([start/0, start_link/0, stop/0]).

start_link() ->
    application:ensure_all_started(),
    plumtree_sup:start_link().

start() ->
    application:ensure_all_started(),
    application:start(plumtree).

stop() ->
    Res = application:stop(plumtree),
    application:stop(crypto),
    application:stop(lager),
    Res.
