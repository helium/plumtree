-module(plumtree_sup).

-behaviour(supervisor).

-export([start_link/0]).

-export([init/1]).

-define(CHILD(I, Type, Timeout), {I, {I, start_link, []}, permanent, Timeout, Type, [I]}).
-define(CHILD(I, Type), ?CHILD(I, Type, 5000)).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = lists:flatten(
                 [
                 ?CHILD(plumtree_peer_service_gossip, worker),
                 ?CHILD(plumtree_broadcast, worker),
                 ?CHILD(plumtree_metadata_exchange_fsm, worker)
                 ]),
    RestartStrategy = {one_for_one, 10, 10},
    {ok, {RestartStrategy, Children}}.

