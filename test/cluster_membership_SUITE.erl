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

-module(cluster_membership_SUITE).

-export([
         %% suite/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0
        ]).

-export([
    singleton_test/1,
    join_test/1,
    join_nonexistant_node_test/1,
    join_self_test/1,
    leave_test/1,
    leave_rejoin_test/1,
    sticky_membership_test/1
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
            end, [jaguar, shadow, thorn, pyros]),
    {ok, _} = ct_cover:add_nodes(Nodes),
    [{nodes, Nodes}|Config].

end_per_testcase(_, _Config) ->
    plumtree_test_utils:pmap(fun(Node) ->ct_slave:stop(Node) end, [jaguar, shadow, thorn, pyros]),
    ok.

all() ->
    [singleton_test, join_test, join_nonexistant_node_test, join_self_test,
    leave_test, leave_rejoin_test, sticky_membership_test].

singleton_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    ok = ct_cover:remove_nodes(Nodes),
    [[Node] = plumtree_test_utils:get_cluster_members(Node) || Node <- Nodes],
    ok.

join_test(Config) ->
    [Node1, Node2 |Nodes] = proplists:get_value(nodes, Config),
    ?assertEqual(ok, rpc:call(Node1, plumtree_peer_service, join, [Node2])),
    Expected = lists:sort([Node1, Node2]),
    ok = plumtree_test_utils:wait_until_joined([Node1, Node2], Expected),
    ?assertEqual(Expected, lists:sort(plumtree_test_utils:get_cluster_members(Node1))),
    ?assertEqual(Expected, lists:sort(plumtree_test_utils:get_cluster_members(Node2))),
    %% make sure the last 2 are still singletons
    [?assertEqual([Node], plumtree_test_utils:get_cluster_members(Node)) || Node <- Nodes],
    ok.

join_nonexistant_node_test(Config) ->
    [Node1|_] = proplists:get_value(nodes, Config),
    ?assertEqual({error, not_reachable}, rpc:call(Node1, plumtree_peer_service, join,
                              [fake@fakehost])),
    ?assertEqual([Node1], plumtree_test_utils:get_cluster_members(Node1)),
    ok.

join_self_test(Config) ->
    [Node1|_] = proplists:get_value(nodes, Config),
    ?assertEqual({error, self_join}, rpc:call(Node1, plumtree_peer_service, join,
                              [Node1])),
    ?assertEqual([Node1], plumtree_test_utils:get_cluster_members(Node1)),
    ok.

leave_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ?assertEqual(ok, rpc:call(Node1, plumtree_peer_service, leave, [[]])),
    Expected2 = lists:sort(OtherNodes),
    ok = plumtree_test_utils:wait_until_left(OtherNodes, Node1),
    %% should be a 3 node cluster now
    [?assertEqual({Node, Expected2}, {Node,
                                      lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- OtherNodes],
    %% node1 should be offline
    ?assertEqual(pang, net_adm:ping(Node1)),
    ok.

leave_rejoin_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [Node2|_Rest] = OtherNodes,
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ?assertEqual(ok, rpc:call(Node1, plumtree_peer_service, leave, [[]])),
    Expected2 = lists:sort(OtherNodes),
    ok = plumtree_test_utils:wait_until_left(OtherNodes, Node1),
    %% should be a 3 node cluster now
    [?assertEqual({Node, Expected2}, {Node,
                                      lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- OtherNodes],
    %% node1 should be offline
    ?assertEqual(pang, net_adm:ping(Node1)),
    plumtree_test_utils:start_node(jaguar, Config, leave_rejoin_test),
    %% rejoin cluster
    ?assertEqual(ok, rpc:call(Node1, plumtree_peer_service, join, [Node2])),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node, 
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ok.

sticky_membership_test(Config) ->
    [Node1|OtherNodes] = Nodes = proplists:get_value(nodes, Config),
    [?assertEqual(ok, rpc:call(Node, plumtree_peer_service, join, [Node1]))
     || Node <- OtherNodes],
    Expected = lists:sort(Nodes),
    ok = plumtree_test_utils:wait_until_joined(Nodes, Expected),
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- Nodes],
    ct_slave:stop(jaguar),
    ok = plumtree_test_utils:wait_until_offline(Node1),
    %% check the membership is the same
    [?assertEqual({Node, Expected}, {Node,
                                     lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- OtherNodes],
    plumtree_test_utils:start_node(jaguar, Config, sticky_membership_test),
    ?assertEqual({Node1, Expected}, {Node1,
                                    lists:sort(plumtree_test_utils:get_cluster_members(Node1))}),
    ct_slave:stop(jaguar),
    ok = plumtree_test_utils:wait_until_offline(Node1),
    [Node2|LastTwo] = OtherNodes,
    ?assertEqual(ok, rpc:call(Node2, plumtree_peer_service, leave, [[]])),
    ok = plumtree_test_utils:wait_until_left(LastTwo, Node2),
    ok = plumtree_test_utils:wait_until_offline(Node2),
    Expected2 = lists:sort(Nodes -- [Node2]),
    [?assertEqual({Node, Expected2}, {Node,
                                      lists:sort(plumtree_test_utils:get_cluster_members(Node))})
     || Node <- LastTwo],
    plumtree_test_utils:start_node(jaguar, Config, sticky_membership_test),
    ok = plumtree_test_utils:wait_until_left([Node1], Node2),
    ?assertEqual({Node1, Expected2}, {Node1,
                                    lists:sort(plumtree_test_utils:get_cluster_members(Node1))}),
    plumtree_test_utils:start_node(shadow, Config, sticky_membership_test),
    %% node 2 should be a singleton now
    ?assertEqual([Node2], plumtree_test_utils:get_cluster_members(Node2)),
    ok.


%% ===================================================================
%% utility functions
%% ===================================================================

