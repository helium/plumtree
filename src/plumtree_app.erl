-module(plumtree_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    _State = plumtree_peer_service_manager:init(),
    case plumtree_sup:start_link() of
        {ok, Pid} ->
            %% do nothing for now
            %% TODO plumtree_broadcast hooks
            {ok, Pid};
        Other ->
            {error, Other}
    end.

stop(_State) ->
    ok.
