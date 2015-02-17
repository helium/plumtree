-module(plumtree).

-export([start/0, start_link/0, stop/0]).

ensure_started(App) ->
    case application:start(App) of
        ok ->
            ok;
        {error, {alread_started, App}} ->
            ok
    end.

start_link() ->
    ensure_started(cyrpto),
    ensure_started(lager),
    plumtree_sup:start_link().

start() ->
    ensure_started(cyrpto),
    ensure_started(lager),
    application:start(plumtree).

stop() ->
    Res = application:stop(plumtree),
    application:stop(cyrpto),
    application:stop(lager),
    Res.
