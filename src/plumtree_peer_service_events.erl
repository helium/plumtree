-module(plumtree_peer_service_events).

-behaviour(gen_event).

%% API
-export([start_link/0,
         add_handler/2,
         add_sup_handler/2,
         add_callback/1,
         add_sup_callback/1,
         update/1
        ]).

%% gen_event callbacks
-export([init/1, handle_event/2, handle_call/2,
         handle_info/2, terminate/2, code_change/3]).

-record(state, { callback }).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_event:start_link({local, ?MODULE}).

add_handler(Handler, Args) ->
    gen_event:add_handler(?MODULE, Handler, Args).

add_sup_handler(Handler, Args) ->
    gen_event:add_sup_handler(?MODULE, Handler, Args).

add_callback(Fn) when is_function(Fn) ->
    gen_event:add_handler(?MODULE, {?MODULE, make_ref()}, [Fn]).

add_sup_callback(Fn) when is_function(Fn) ->
    gen_event:add_sup_handler(?MODULE, {?MODULE, make_ref()}, [Fn]).

update(LocalState) ->
    gen_event:notify(?MODULE, {update, LocalState}).

%% ===================================================================
%% gen_event callbacks
%% ===================================================================

init([Fn]) ->
    {ok, LocalState} = plumtree_peer_service_manager:get_local_state(),
    Members = riak_dt_orswot:value(LocalState),
    Fn(Members),
    {ok, #state { callback = Fn }}.

handle_event({update, LocalState}, State) ->
    (State#state.callback)(LocalState),
    {ok, State}.

handle_call(_Request, State) ->
    {ok, ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
