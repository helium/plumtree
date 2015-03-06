%% -------------------------------------------------------------------
%%
%% Copyright (c) 2015 Helium Systems, Inc.  All Rights Reserved.
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(metadata_SUITE).

-export([
         %% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0
        ]).

-export([
    read_write_delete_test/1,
    partitioned_cluster_test/1,
    siblings_test/1
        ]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").


%% ===================================================================
%% common_test callbacks
%% ===================================================================

init_per_suite(_Config) ->
    lager:start(),
    %% this might help, might not...
    os:cmd(os:find_executable("epmd")++" -daemon"),
    {ok, Hostname} = inet:gethostname(),
    case net_kernel:start([list_to_atom("runner@"++Hostname), shortnames]) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok
    end,
    lager:info("node name ~p", [node()]),
    _Config.

end_per_suite(_Config) ->
    application:stop(lager),
    _Config.

init_per_testcase(Case, Config) ->
    Nodes = plumtree_test_utils:pmap(fun(N) ->
                    plumtree_test_utils:start_node(N, Config, Case)
            end, [electra, katana, flail, gargoyle]),
    {ok, _} = ct_cover:add_nodes(Nodes),
    [{nodes, Nodes}|Config].

end_per_testcase(_, _Config) ->
    plumtree_test_utils:pmap(fun(Node) ->ct_slave:stop(Node) end, [electra, katana, flail, gargoyle]),
    ok.

all() ->
    [read_write_delete_test, partitioned_cluster_test, siblings_test].

read_write_delete_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ?assertEqual(undefined, get_metadata(Node1, {foo, bar}, baz, [])),
    ok = put_metadata(Node1, {foo, bar}, baz, quux, []),
    ?assertEqual(quux, get_metadata(Node1, {foo, bar}, baz, [])),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, quux),
    ok = put_metadata(Node1, {foo, bar}, baz, norf, []),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, norf),
    ok = delete_metadata(Node1, {foo, bar}, baz),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, undefined),
    ok.

partitioned_cluster_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ok = wait_until_converged(Nodes, {foo, bar}, baz, undefined),
    ok = put_metadata(Node1, {foo, bar}, baz, quux, []),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, quux),
    {ANodes, BNodes} = lists:split(2, Nodes),
    plumtree_test_utils:partition_cluster(ANodes, BNodes),
    %% write to one side
    ok = put_metadata(Node1, {foo, bar}, baz, norf, []),
    %% check that whole side has the new value
    ok = wait_until_converged(ANodes, {foo, bar}, baz, norf),
    %% the far side should have the old value
    ok = wait_until_converged(BNodes, {foo, bar}, baz, quux),
    plumtree_test_utils:heal_cluster(ANodes, BNodes),
    %% all the nodes should see the new value
    ok = wait_until_converged(Nodes, {foo, bar}, baz, norf),
    ok.

siblings_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ok = wait_until_converged(Nodes, {foo, bar}, baz, undefined),
    ok = put_metadata(Node1, {foo, bar}, baz, quux, []),
    ok = put_metadata(Node1, {foo, bar}, canary, 1, []),
    ok = wait_until_converged(Nodes, {foo, bar}, baz, quux),
    ok = wait_until_converged(Nodes, {foo, bar}, canary, 1),
    {ANodes, BNodes} = lists:split(2, Nodes),
    plumtree_test_utils:partition_cluster(ANodes, BNodes),
    %% write to one side
    ok = put_metadata(Node1, {foo, bar}, baz, norf, []),
    ok = put_metadata(Node1, {foo, bar}, canary, 2, []),
    %% check that whole side has the new value
    ok = wait_until_converged(ANodes, {foo, bar}, baz, norf),
    ok = wait_until_converged(ANodes, {foo, bar}, canary, 2),
    %% the far side should have the old value
    ok = wait_until_converged(BNodes, {foo, bar}, baz, quux),
    ok = wait_until_converged(BNodes, {foo, bar}, canary, 1),
    %% write a competing value to the other side
    [Node3|_] = BNodes,
    ok = put_metadata(Node3, {foo, bar}, baz, mork, []),
    ok = wait_until_converged(BNodes, {foo, bar}, baz, mork),
    plumtree_test_utils:heal_cluster(ANodes, BNodes),
    %% block until the canary key converges
    ok = wait_until_converged(Nodes, {foo, bar}, canary, 2),
    %% make sure we have siblings, but don't resolve them yet
    ok = wait_until_sibling(Nodes, {foo, bar}, baz),
    %% resolve the sibling
    spork = get_metadata(Node1, {foo, bar}, baz, [{resolver, fun(_A, _B) ->
                            spork end}, {allow_put, false}]),
    %% without allow_put set, all the siblings are still there...
    ok = wait_until_sibling(Nodes, {foo, bar}, baz),
    %% resolve the sibling and write it back
    spork = get_metadata(Node1, {foo, bar}, baz, [{resolver, fun(_A, _B) ->
                            spork end}, {allow_put, true}]),
    %% check all the nodes see the resolution
    ok = wait_until_converged(Nodes, {foo, bar}, baz, spork),
    ok.


%% ===================================================================
%% utility functions
%% ===================================================================

get_metadata(Node, Prefix, Key, Opts) ->
    rpc:call(Node, plumtree_metadata, get, [Prefix, Key, Opts]).

put_metadata(Node, Prefix, Key, ValueOrFun, Opts) ->
    rpc:call(Node, plumtree_metadata, put, [Prefix, Key, ValueOrFun, Opts]).

delete_metadata(Node, Prefix, Key) ->
    rpc:call(Node, plumtree_metadata, delete, [Prefix, Key]).

wait_until_converged(Nodes, Prefix, Key, ExpectedValue) ->
    plumtree_test_utils:wait_until(fun() ->
                lists:all(fun(X) -> X == true end,
                          plumtree_test_utils:pmap(fun(Node) ->
                                ExpectedValue == get_metadata(Node, Prefix,
                                                              Key,
                                                              [{allow_put,
                                                                false}])
                        end, Nodes))
        end, 60*2, 500).


wait_until_sibling(Nodes, Prefix, Key) ->
    plumtree_test_utils:wait_until(fun() ->
                lists:all(fun(X) -> X == true end,
                          plumtree_test_utils:pmap(fun(Node) ->
                                case rpc:call(Node, plumtree_metadata_manager,
                                              get, [{Prefix, Key}]) of
                                    undefined -> false;
                                    Value ->
                                        rpc:call(Node,
                                                 plumtree_metadata_object,
                                                 value_count, [Value]) > 1
                                end
                        end, Nodes))
        end, 60*2, 500).
